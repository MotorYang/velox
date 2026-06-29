import Foundation
import Combine
@preconcurrency import Citadel
@preconcurrency import NIOCore
import NIOFoundationCompat
internal import NIOSSH

@MainActor
final class TerminalSessionManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isShellActive = false
    @Published private(set) var didShellExit = false
    @Published private(set) var currentRemotePath = "/"
    @Published private(set) var remoteTitlePrefix: String?
    @Published private(set) var remoteFiles: [RemoteFile] = []
    @Published private(set) var isSFTPLoading = false
    @Published private(set) var sftpStatusMessage: String?
    @Published private(set) var activeTransfers: [SFTPTransferProgress] = []
    @Published var uploadProgress = 0.0
    @Published var showUploadIndicator = false
    @Published var statusMessage = "Connecting to SSH..."
    var onShellExit: (() -> Void)?
    
    private enum TerminalInputEvent: Sendable {
        case send([UInt8])
        case resize(cols: Int, rows: Int)
    }
    
    private var client: SSHClient?
    private var sftp: SFTPClient?
    private var currentConnection: SSHConnectionConfiguration?
    private var reconnectTask: Task<Void, Never>?
    private var isIntentionallyDisconnecting = false
    private var shellTask: Task<Void, Never>?
    private var shellSessionID: UUID?
    private var inputContinuation: AsyncStream<TerminalInputEvent>.Continuation?
    private var transferProgressStates: [UUID: SFTPTransferProgress] = [:]
    private var pausedTransferIDs = Set<UUID>()
    private var canceledTransferIDs = Set<UUID>()
    private var transferCancellationToken = UUID()
    private let transferChunkSize = 256 * 1024
    private let progressUpdateInterval: TimeInterval = 1.0 / 30.0
    
    deinit {
        shellTask?.cancel()
        inputContinuation?.finish()
    }
    
    func connect(host: String, port: Int = 22, user: String, auth: SSHAuthentication) async throws {
        try await disconnect()

        let configuration = SSHConnectionConfiguration(host: host, port: port, user: user, auth: auth)
        currentConnection = configuration
        isIntentionallyDisconnecting = false
        try await establishConnection(configuration)
    }

    private func establishConnection(_ configuration: SSHConnectionConfiguration) async throws {
        didShellExit = false
        statusMessage = "Connecting to \(configuration.user)@\(configuration.host):\(configuration.port)..."
        
        let authenticationMethod = try configuration.auth.makeCitadelMethod(username: configuration.user)
        let sshClient = try await SSHClient.connect(
            host: configuration.host,
            port: configuration.port,
            authenticationMethod: authenticationMethod,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )
        
        sshClient.onDisconnect { [weak self] in
            guard let manager = self else { return }
            Task { @MainActor [manager] in
                manager.isConnected = false
                manager.isShellActive = false
                manager.statusMessage = "SSH connection disconnected"
                manager.scheduleReconnectIfNeeded()
            }
        }
        
        self.client = sshClient
        self.sftp = try await sshClient.openSFTP()
        self.isConnected = true
        self.remoteTitlePrefix = "\(configuration.user)@\(configuration.host)"
        self.statusMessage = "SSH connected"
        
        try await fetchRemoteFiles(at: ".")
    }
    
    func disconnect() async throws {
        isIntentionallyDisconnecting = true
        reconnectTask?.cancel()
        reconnectTask = nil
        cancelActiveTransfers()
        shellTask?.cancel()
        shellTask = nil
        shellSessionID = nil
        inputContinuation?.finish()
        inputContinuation = nil
        
        if let sftp {
            try? await sftp.close()
        }
        
        if let client {
            try? await client.close()
        }
        
        client = nil
        sftp = nil
        isConnected = false
        isShellActive = false
        didShellExit = false
        remoteFiles = []
        currentRemotePath = "/"
        remoteTitlePrefix = nil
        isSFTPLoading = false
        sftpStatusMessage = nil
        activeTransfers = []
        transferProgressStates = [:]
        currentConnection = nil
        statusMessage = "SSH connection closed"
    }

    func cancelActiveTransfers() {
        transferCancellationToken = UUID()
        transferProgressStates.removeAll()
        pausedTransferIDs.removeAll()
        canceledTransferIDs.removeAll()
        activeTransfers = []
        showUploadIndicator = false
        uploadProgress = 0
    }

    func pauseTransfer(_ id: UUID) {
        guard var progress = transferProgressStates[id], progress.status == .running else {
            return
        }

        pausedTransferIDs.insert(id)
        progress.status = .paused
        progress.updatedAt = Date()
        transferProgressStates[id] = progress
        publishTransferStates()
    }

    func resumeTransfer(_ id: UUID) {
        guard var progress = transferProgressStates[id], progress.status == .paused else {
            return
        }

        pausedTransferIDs.remove(id)
        progress.status = .running
        progress.updatedAt = Date()
        transferProgressStates[id] = progress
        publishTransferStates()
    }

    func cancelTransfer(_ id: UUID) {
        canceledTransferIDs.insert(id)
        pausedTransferIDs.remove(id)
        transferProgressStates.removeValue(forKey: id)
        publishTransferStates()
    }
    
    func fetchRemoteFiles(at path: String) async throws {
        guard let sftp else {
            return
        }

        isSFTPLoading = true
        sftpStatusMessage = "Loading \(path)..."
        defer {
            isSFTPLoading = false
        }

        do {
            let resolvedPath = try await sftp.getRealPath(atPath: path)
            let entries = try await sftp.listDirectory(atPath: resolvedPath)
                .flatMap(\.components)
                .filter { $0.filename != "." && $0.filename != ".." }
                .map { RemoteFile(component: $0, parentPath: resolvedPath) }
                .sorted {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory && !$1.isDirectory
                    }

                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }

            currentRemotePath = resolvedPath
            remoteFiles = entries
            sftpStatusMessage = "\(entries.count) items"
        } catch {
            sftpStatusMessage = error.localizedDescription
            throw error
        }
    }
    
    func uploadFile(localURL: URL) async throws {
        try await uploadItems(localURLs: [localURL])
    }

    func uploadItems(localURLs: [URL]) async throws {
        let urls = localURLs.filter { !$0.lastPathComponent.isEmpty }
        guard !urls.isEmpty else {
            return
        }

        let destinationPath = currentRemotePath
        let cancellationToken = transferCancellationToken
        let totalBytes = try await Task.detached {
            try Self.localTransferSize(for: urls)
        }.value

        let transferID = beginTransfer(.upload, itemName: Self.transferTitle(for: urls), totalBytes: totalBytes)

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask { [self, destinationPath, transferID, url] in
                        try await self.uploadItem(
                            localURL: url,
                            to: self.joinRemotePath(destinationPath, url.lastPathComponent),
                            transferID: transferID,
                            cancellationToken: cancellationToken
                        )
                    }
                }

                try await group.waitForAll()
            }

            completeTransfer(transferID, message: "Uploaded \(Self.transferTitle(for: urls))")
            try await fetchRemoteFiles(at: currentRemotePath)
            scheduleTransferDismissal(transferID)
        } catch is CancellationError {
            removeTransfer(transferID)
            throw CancellationError()
        } catch {
            failTransfer(transferID, error)
            throw error
        }
    }

    func downloadFile(_ remoteFile: RemoteFile, to localURL: URL) async throws {
        try await downloadFile(remoteFile, to: localURL, overwrite: true)
    }

    func downloadFile(_ remoteFile: RemoteFile, to localURL: URL, overwrite: Bool) async throws {
        let destinationURL = remoteFile.isDirectory ? localURL.appendingPathComponent(remoteFile.name, isDirectory: true) : localURL
        if !overwrite, FileManager.default.fileExists(atPath: destinationURL.path) {
            throw SFTPActionError.itemAlreadyExists(destinationURL.lastPathComponent)
        }

        let sftp = try await waitForActiveSFTP(transferID: nil, cancellationToken: transferCancellationToken)
        let totalBytes = try await remoteTransferSize(remoteFile, using: sftp)
        let transferID = beginTransfer(.download, itemName: remoteFile.name, totalBytes: totalBytes)
        let cancellationToken = transferCancellationToken
        
        do {
            try await downloadItem(remoteFile, to: destinationURL, transferID: transferID, cancellationToken: cancellationToken)
            completeTransfer(transferID, message: "Downloaded \(remoteFile.name)")
            scheduleTransferDismissal(transferID)
        } catch is CancellationError {
            removeTransfer(transferID)
            throw CancellationError()
        } catch {
            failTransfer(transferID, error)
            throw error
        }
    }

    func remoteItemExists(named name: String) async -> Bool {
        guard !name.isEmpty else {
            return false
        }

        do {
            let sftp = try await waitForActiveSFTP(transferID: nil, cancellationToken: transferCancellationToken)
            _ = try await sftp.getAttributes(at: remotePath(appending: name))
            return true
        } catch {
            return false
        }
    }

    func changeRemoteDirectory(to path: String) async throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw SFTPActionError.invalidPath
        }

        try await fetchRemoteFiles(at: trimmedPath)
    }

    func createRemoteDirectory(named name: String) async throws {
        guard let sftp else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRemoteName(trimmedName) else {
            throw SFTPActionError.invalidName
        }

        var attributes = SFTPFileAttributes.none
        attributes.permissions = 0o755
        try await sftp.createDirectory(atPath: remotePath(appending: trimmedName), attributes: attributes)
        try await fetchRemoteFiles(at: currentRemotePath)
    }

    func renameRemoteFile(_ remoteFile: RemoteFile, to newName: String) async throws {
        guard let sftp else {
            return
        }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidRemoteName(trimmedName) else {
            throw SFTPActionError.invalidName
        }

        let newPath = remotePath(appending: trimmedName)
        try await sftp.rename(at: remoteFile.path, to: newPath)
        try await fetchRemoteFiles(at: currentRemotePath)
    }

    func deleteRemoteFile(_ remoteFile: RemoteFile) async throws {
        guard let sftp else {
            return
        }

        if remoteFile.isDirectory {
            try await deleteRemoteDirectory(remoteFile.path, using: sftp)
        } else {
            try await sftp.remove(at: remoteFile.path)
        }

        try await fetchRemoteFiles(at: currentRemotePath)
    }

    func goToParentRemoteDirectory() async throws {
        guard currentRemotePath != "/" else {
            return
        }

        try await fetchRemoteFiles(at: parentPath(of: currentRemotePath))
    }
    
    func startTerminalBridge(initialCols: Int = 80, initialRows: Int = 24, onOutput: @escaping @MainActor (ArraySlice<UInt8>) -> Void) {
        guard shellTask == nil, !didShellExit, let client else {
            return
        }
        
        let stream = AsyncStream<TerminalInputEvent> { continuation in
            self.inputContinuation = continuation
        }
        let shellSessionID = UUID()
        self.shellSessionID = shellSessionID
        
        isShellActive = true
        
        shellTask = Task.detached { [weak self] in
            
            do {
                try await client.withPTY(
                    .init(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: initialCols,
                        terminalRowHeight: initialRows,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: .init([.ECHO: 1])
                    )
                ) { inbound, outbound in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for try await output in inbound {
                                switch output {
                                case .stdout(var buffer), .stderr(var buffer):
                                    let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
                                    await onOutput(bytes[...])
                                }
                            }
                        }
                        
                        group.addTask {
                            for await event in stream {
                                switch event {
                                case .send(let bytes):
                                    try await outbound.write(ByteBuffer(bytes: bytes))
                                case .resize(let cols, let rows):
                                    try await outbound.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
                                }
                            }
                        }
                        
                        try await group.next()
                        group.cancelAll()
                    }
                }
            } catch is CancellationError {
            } catch {
                let message = "SSH Connection Interrupted: \(error.localizedDescription)"
                await MainActor.run { [weak self, message] in
                    self?.statusMessage = message
                }
            }
            
            await MainActor.run { [weak self, shellSessionID] in
                guard let self = self, self.shellSessionID == shellSessionID else { return }
                
                // 标记状态
                self.didShellExit = true
                self.isShellActive = false
                self.statusMessage = "Terminal session ended"
                
                self.onShellExit?()
                
                // 释放持有的临时任务句柄
                self.shellTask = nil
                self.shellSessionID = nil
                self.inputContinuation = nil
            }
        }
    }
    
    func syncRemoteFolder(to directory: String?) {
        guard let directory, !directory.isEmpty else {
            return
        }
        
        let path: String
        if let url = URL(string: directory), url.isFileURL {
            path = url.path
        } else {
            path = directory
        }
        
        Task {
            try? await fetchRemoteFiles(at: path)
        }
    }
    
    func sendInputToRemote(bytes: ArraySlice<UInt8>) {
        inputContinuation?.yield(.send(Array(bytes)))
    }
    
    func resizeRemoteTerminal(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else {
            return
        }
        
        inputContinuation?.yield(.resize(cols: cols, rows: rows))
    }
    
    private func remotePath(appending fileName: String) -> String {
        let prefix = currentRemotePath == "/" ? "" : currentRemotePath
        return "\(prefix)/\(fileName)"
    }

    private func uploadItem(localURL: URL, to remotePath: String, transferID: UUID, cancellationToken: UUID) async throws {
        _ = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
        let shouldStopAccessing = localURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                localURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try localURL.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues.isDirectory == true {
            let sftp = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
            try? await sftp.createDirectory(atPath: remotePath, attributes: directoryAttributes)
            let children = try FileManager.default.contentsOfDirectory(
                at: localURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: []
            )

            for child in children {
                try await uploadItem(localURL: child, to: joinRemotePath(remotePath, child.lastPathComponent), transferID: transferID, cancellationToken: cancellationToken)
            }
        } else {
            sftpStatusMessage = "Uploading \(localURL.lastPathComponent)..."
            try await uploadFileContents(localURL: localURL, to: remotePath, transferID: transferID, cancellationToken: cancellationToken)
        }
    }

    private func uploadFileContents(localURL: URL, to remotePath: String, transferID: UUID, cancellationToken: UUID) async throws {
        let handle = try FileHandle(forReadingFrom: localURL)
        defer {
            try? handle.close()
        }

        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            _ = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: transferChunkSize) ?? Data()
            guard !data.isEmpty else {
                break
            }

            do {
                let sftp = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
                let writeOffset = offset
                let flags: SFTPOpenFileFlags = writeOffset == 0 ? [.write, .create, .truncate] : [.write, .create]
                try checkTransferCanProgress(transferID: transferID, cancellationToken: cancellationToken)
                try await sftp.withFile(filePath: remotePath, flags: flags) { file in
                    try await file.write(ByteBuffer(data: data), at: writeOffset)
                }
                try checkTransferCanProgress(transferID: transferID, cancellationToken: cancellationToken)
                offset += UInt64(data.count)
                self.advanceTransfer(transferID, by: UInt64(data.count), itemName: localURL.lastPathComponent)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                markDisconnectedForTransferRetry(error)
            }
        }
    }

    private func downloadItem(_ remoteFile: RemoteFile, to localURL: URL, transferID: UUID, cancellationToken: UUID) async throws {
        _ = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
        if remoteFile.isDirectory {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true, attributes: nil)
            let sftp = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
            let children = try await remoteDirectoryEntries(at: remoteFile.path, using: sftp)
            for child in children {
                try await downloadItem(child, to: localURL.appendingPathComponent(child.name, isDirectory: child.isDirectory), transferID: transferID, cancellationToken: cancellationToken)
            }
        } else {
            sftpStatusMessage = "Downloading \(remoteFile.name)..."
            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try await downloadFileContents(remoteFile, to: localURL, transferID: transferID, cancellationToken: cancellationToken)
        }
    }

    private func downloadFileContents(_ remoteFile: RemoteFile, to localURL: URL, transferID: UUID, cancellationToken: UUID) async throws {
        let handle = try FileHandle(forWritingTo: Self.prepareDownloadFile(at: localURL))
        defer {
            try? handle.close()
        }

        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            _ = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
            do {
                let sftp = try await waitForActiveSFTP(transferID: transferID, cancellationToken: cancellationToken)
                let readOffset = offset
                try checkTransferCanProgress(transferID: transferID, cancellationToken: cancellationToken)
                let data: Data = try await sftp.withFile(filePath: remoteFile.path, flags: .read) { [transferChunkSize] file in
                    var buffer = try await file.read(from: readOffset, length: UInt32(transferChunkSize))
                    return buffer.readData(length: buffer.readableBytes) ?? Data()
                }
                guard !data.isEmpty else { break }
                try checkTransferCanProgress(transferID: transferID, cancellationToken: cancellationToken)

                try handle.seek(toOffset: readOffset)
                try handle.write(contentsOf: data)
                offset += UInt64(data.count)
                self.advanceTransfer(transferID, by: UInt64(data.count), itemName: remoteFile.name)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                markDisconnectedForTransferRetry(error)
            }
        }
    }

    private func remoteTransferSize(_ remoteFile: RemoteFile, using sftp: SFTPClient) async throws -> UInt64 {
        if !remoteFile.isDirectory {
            return remoteFile.size ?? 0
        }

        let children = try await remoteDirectoryEntries(at: remoteFile.path, using: sftp)
        var total: UInt64 = 0
        for child in children {
            total += try await remoteTransferSize(child, using: sftp)
        }
        return total
    }

    private func remoteDirectoryEntries(at path: String, using sftp: SFTPClient) async throws -> [RemoteFile] {
        try await sftp.listDirectory(atPath: path)
            .flatMap(\.components)
            .filter { $0.filename != "." && $0.filename != ".." }
            .map { RemoteFile(component: $0, parentPath: path) }
    }

    private func deleteRemoteDirectory(_ path: String, using sftp: SFTPClient) async throws {
        let children = try await remoteDirectoryEntries(at: path, using: sftp)
        for child in children {
            if child.isDirectory {
                try await deleteRemoteDirectory(child.path, using: sftp)
            } else {
                try await sftp.remove(at: child.path)
            }
        }

        try await sftp.rmdir(at: path)
    }

    private var directoryAttributes: SFTPFileAttributes {
        var attributes = SFTPFileAttributes.none
        attributes.permissions = 0o755
        return attributes
    }

    private func beginTransfer(_ kind: SFTPTransferKind, itemName: String, totalBytes: UInt64) -> UUID {
        let id = UUID()
        let progress = SFTPTransferProgress(id: id, kind: kind, itemName: itemName, status: .running, completedBytes: 0, totalBytes: totalBytes, updatedAt: Date())
        transferProgressStates[id] = progress
        publishTransferStates()
        sftpStatusMessage = progress.statusText
        uploadProgress = 0
        showUploadIndicator = activeTransfers.contains { $0.kind == .upload }
        return id
    }

    private func advanceTransfer(_ id: UUID, by byteCount: UInt64, itemName: String) {
        guard var progress = transferProgressStates[id] else {
            return
        }

        guard !pausedTransferIDs.contains(id), !canceledTransferIDs.contains(id) else {
            return
        }

        progress.itemName = itemName
        progress.status = .running
        progress.completedBytes = min(progress.completedBytes + byteCount, progress.totalBytes)

        let now = Date()
        let shouldPublish = progress.totalBytes == 0
            || progress.completedBytes == progress.totalBytes
            || now.timeIntervalSince(progress.updatedAt) >= progressUpdateInterval

        transferProgressStates[id] = progress

        guard shouldPublish else {
            return
        }

        progress.updatedAt = now
        transferProgressStates[id] = progress
        publishTransferStates()
        uploadProgress = progress.fractionCompleted
        sftpStatusMessage = progress.statusText
    }

    private func completeTransfer(_ id: UUID, message: String) {
        if var progress = transferProgressStates[id] {
            progress.completedBytes = progress.totalBytes
            progress.status = .completed
            progress.updatedAt = Date()
            transferProgressStates[id] = progress
            publishTransferStates()
            uploadProgress = 1
        }
        sftpStatusMessage = message
    }

    private func failTransfer(_ id: UUID, _ error: Error) {
        sftpStatusMessage = error.localizedDescription
        transferProgressStates.removeValue(forKey: id)
        publishTransferStates()
        uploadProgress = 0
    }

    private func removeTransfer(_ id: UUID) {
        transferProgressStates.removeValue(forKey: id)
        publishTransferStates()
        uploadProgress = 0
    }

    private func scheduleTransferDismissal(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            self.transferProgressStates.removeValue(forKey: id)
            self.publishTransferStates()
            self.uploadProgress = 0
        }
    }

    private func publishTransferStates() {
        activeTransfers = transferProgressStates.values.sorted {
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }

            return $0.itemName.localizedStandardCompare($1.itemName) == .orderedAscending
        }
        showUploadIndicator = activeTransfers.contains { $0.kind == .upload }
    }

    private func checkTransferActive(_ token: UUID) throws {
        guard isConnected, transferCancellationToken == token else {
            throw CancellationError()
        }
    }

    private func waitForActiveSFTP(transferID: UUID?, cancellationToken: UUID) async throws -> SFTPClient {
        while true {
            try Task.checkCancellation()
            guard transferCancellationToken == cancellationToken else {
                throw CancellationError()
            }

            if let transferID {
                try checkTransferCanProgress(transferID: transferID, cancellationToken: cancellationToken)

                if pausedTransferIDs.contains(transferID) {
                    try await Task.sleep(for: .milliseconds(120))
                    continue
                }
            }

            if isConnected, let sftp {
                return sftp
            }

            scheduleReconnectIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func checkTransferCanProgress(transferID: UUID, cancellationToken: UUID) throws {
        guard transferCancellationToken == cancellationToken,
              !canceledTransferIDs.contains(transferID),
              transferProgressStates[transferID] != nil
        else {
            throw CancellationError()
        }
    }

    private func markDisconnectedForTransferRetry(_ error: Error) {
        isConnected = false
        isShellActive = false
        sftpStatusMessage = "Connection interrupted. Reconnecting..."
        statusMessage = "SSH connection interrupted: \(error.localizedDescription)"
        scheduleReconnectIfNeeded()
    }

    private func scheduleReconnectIfNeeded() {
        guard !isIntentionallyDisconnecting, currentConnection != nil else {
            return
        }

        guard reconnectTask == nil else {
            return
        }

        reconnectTask = Task { @MainActor in
            let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]
            var attempt = 0

            while !Task.isCancelled, !isIntentionallyDisconnecting, !isConnected {
                guard let configuration = currentConnection else { break }
                let delay = delays[min(attempt, delays.count - 1)]
                statusMessage = "Reconnecting SSH..."
                try? await Task.sleep(for: delay)

                do {
                    try? await sftp?.close()
                    try? await client?.close()
                    sftp = nil
                    client = nil
                    try await establishConnection(configuration)
                    reconnectTask = nil
                    return
                } catch {
                    attempt += 1
                    statusMessage = "Reconnect failed: \(error.localizedDescription)"
                }
            }

            reconnectTask = nil
        }
    }

    private func joinRemotePath(_ directory: String, _ child: String) -> String {
        let normalizedDirectory = directory == "/" ? "" : directory
        return "\(normalizedDirectory)/\(child)"
    }

    nonisolated private static func localTransferSize(for urls: [URL]) throws -> UInt64 {
        var total: UInt64 = 0
        for url in urls {
            total += try localTransferSize(for: url)
        }
        return total
    }

    nonisolated private static func localTransferSize(for url: URL) throws -> UInt64 {
        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if resourceValues.isDirectory == true {
            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: []
            )
            return try children.reduce(UInt64(0)) { partialResult, child in
                partialResult + (try localTransferSize(for: child))
            }
        }

        if let fileSize = resourceValues.fileSize {
            return UInt64(fileSize)
        }

        if let allocatedSize = resourceValues.totalFileAllocatedSize {
            return UInt64(allocatedSize)
        }

        return 0
    }

    nonisolated private static func prepareDownloadFile(at url: URL) throws -> URL {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.close()
        return url
    }

    nonisolated private static func transferTitle(for urls: [URL]) -> String {
        guard urls.count != 1 else {
            return urls[0].lastPathComponent
        }

        return "\(urls.count) items"
    }

    private func parentPath(of path: String) -> String {
        let normalizedPath = path == "/" ? path : path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPath.isEmpty else {
            return "/"
        }

        let components = normalizedPath.split(separator: "/").map(String.init)
        guard components.count > 1 else {
            return "/"
        }

        return "/" + components.dropLast().joined(separator: "/")
    }

    private func isValidRemoteName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/")
    }
}

enum SFTPActionError: LocalizedError {
    case invalidName
    case invalidPath
    case itemAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Name cannot be empty or contain '/'."
        case .invalidPath:
            return "Path cannot be empty."
        case .itemAlreadyExists(let name):
            return "\(name) already exists."
        }
    }
}

private struct SSHConnectionConfiguration {
    let host: String
    let port: Int
    let user: String
    let auth: SSHAuthentication
}

enum SFTPTransferKind: String, Sendable {
    case upload = "Uploading"
    case download = "Downloading"
}

enum SFTPTransferStatus: String, Sendable {
    case running
    case paused
    case completed
}

struct SFTPTransferProgress: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: SFTPTransferKind
    var itemName: String
    var status: SFTPTransferStatus
    var completedBytes: UInt64
    let totalBytes: UInt64
    var updatedAt: Date

    var fractionCompleted: Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    var statusText: String {
        "\(kind.rawValue) \(itemName)"
    }

    var byteText: String {
        guard totalBytes > 0 else {
            return "Preparing..."
        }

        let completed = ByteCountFormatter.string(fromByteCount: Int64(completedBytes), countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        return "\(completed) / \(total)"
    }
}
