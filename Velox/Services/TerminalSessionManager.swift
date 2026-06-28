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
    @Published private(set) var activeTransfer: SFTPTransferProgress?
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
    private var shellTask: Task<Void, Never>?
    private var shellSessionID: UUID?
    private var inputContinuation: AsyncStream<TerminalInputEvent>.Continuation?
    private var transferProgressState: SFTPTransferProgress?
    private let transferChunkSize = 256 * 1024
    private let progressUpdateInterval: TimeInterval = 1.0 / 30.0
    
    deinit {
        shellTask?.cancel()
        inputContinuation?.finish()
    }
    
    func connect(host: String, port: Int = 22, user: String, auth: SSHAuthentication) async throws {
        try await disconnect()
        
        didShellExit = false
        statusMessage = "Connecting to \(user)@\(host):\(port)..."
        
        let authenticationMethod = try auth.makeCitadelMethod(username: user)
        let sshClient = try await SSHClient.connect(
            host: host,
            port: port,
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
            }
        }
        
        self.client = sshClient
        self.sftp = try await sshClient.openSFTP()
        self.isConnected = true
        self.remoteTitlePrefix = "\(user)@\(host)"
        self.statusMessage = "SSH connected"
        
        try await fetchRemoteFiles(at: ".")
    }
    
    func disconnect() async throws {
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
        activeTransfer = nil
        transferProgressState = nil
        statusMessage = "SSH connection closed"
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
        guard let sftp else {
            return
        }

        let urls = localURLs.filter { !$0.lastPathComponent.isEmpty }
        guard !urls.isEmpty else {
            return
        }

        let totalBytes = try await Task.detached {
            try Self.localTransferSize(for: urls)
        }.value

        beginTransfer(.upload, itemName: Self.transferTitle(for: urls), totalBytes: totalBytes)

        do {
            for url in urls {
                try await uploadItem(localURL: url, to: remotePath(appending: url.lastPathComponent), using: sftp)
            }

            completeTransfer(message: "Uploaded \(Self.transferTitle(for: urls))")
            try await fetchRemoteFiles(at: currentRemotePath)
            scheduleTransferDismissal()
        } catch {
            failTransfer(error)
            throw error
        }
    }

    func downloadFile(_ remoteFile: RemoteFile, to localURL: URL) async throws {
        guard let sftp else {
            return
        }

        let destinationURL = remoteFile.isDirectory ? localURL.appendingPathComponent(remoteFile.name, isDirectory: true) : localURL
        let totalBytes = try await remoteTransferSize(remoteFile, using: sftp)
        beginTransfer(.download, itemName: remoteFile.name, totalBytes: totalBytes)
        
        do {
            try await downloadItem(remoteFile, to: destinationURL, using: sftp)
            completeTransfer(message: "Downloaded \(remoteFile.name)")
            scheduleTransferDismissal()
        } catch {
            failTransfer(error)
            throw error
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

    private func uploadItem(localURL: URL, to remotePath: String, using sftp: SFTPClient) async throws {
        let shouldStopAccessing = localURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                localURL.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try localURL.resourceValues(forKeys: [.isDirectoryKey])
        if resourceValues.isDirectory == true {
            try? await sftp.createDirectory(atPath: remotePath, attributes: directoryAttributes)
            let children = try FileManager.default.contentsOfDirectory(
                at: localURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: []
            )

            for child in children {
                try await uploadItem(localURL: child, to: joinRemotePath(remotePath, child.lastPathComponent), using: sftp)
            }
        } else {
            sftpStatusMessage = "Uploading \(localURL.lastPathComponent)..."
            try await uploadFileContents(localURL: localURL, to: remotePath, using: sftp)
        }
    }

    private func uploadFileContents(localURL: URL, to remotePath: String, using sftp: SFTPClient) async throws {
        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { [transferChunkSize] file in
            let handle = try FileHandle(forReadingFrom: localURL)
            defer {
                try? handle.close()
            }

            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let data = try handle.read(upToCount: transferChunkSize) ?? Data()
                guard !data.isEmpty else {
                    break
                }

                try await file.write(ByteBuffer(data: data), at: offset)
                offset += UInt64(data.count)
                await self.advanceTransfer(by: UInt64(data.count), itemName: localURL.lastPathComponent)
            }
        }
    }

    private func downloadItem(_ remoteFile: RemoteFile, to localURL: URL, using sftp: SFTPClient) async throws {
        if remoteFile.isDirectory {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true, attributes: nil)
            let children = try await remoteDirectoryEntries(at: remoteFile.path, using: sftp)
            for child in children {
                try await downloadItem(child, to: localURL.appendingPathComponent(child.name, isDirectory: child.isDirectory), using: sftp)
            }
        } else {
            sftpStatusMessage = "Downloading \(remoteFile.name)..."
            try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try await downloadFileContents(remoteFile, to: localURL, using: sftp)
        }
    }

    private func downloadFileContents(_ remoteFile: RemoteFile, to localURL: URL, using sftp: SFTPClient) async throws {
        try await sftp.withFile(filePath: remoteFile.path, flags: .read) { [transferChunkSize] file in
            let handle = try FileHandle(forWritingTo: Self.prepareDownloadFile(at: localURL))
            defer {
                try? handle.close()
            }

            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                var buffer = try await file.read(from: offset, length: UInt32(transferChunkSize))
                guard let data = buffer.readData(length: buffer.readableBytes), !data.isEmpty else {
                    break
                }

                try handle.write(contentsOf: data)
                offset += UInt64(data.count)
                await self.advanceTransfer(by: UInt64(data.count), itemName: remoteFile.name)
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

    private func beginTransfer(_ kind: SFTPTransferKind, itemName: String, totalBytes: UInt64) {
        let progress = SFTPTransferProgress(kind: kind, itemName: itemName, completedBytes: 0, totalBytes: totalBytes, updatedAt: Date())
        transferProgressState = progress
        activeTransfer = progress
        sftpStatusMessage = progress.statusText
        uploadProgress = 0
        showUploadIndicator = kind == .upload
    }

    private func advanceTransfer(by byteCount: UInt64, itemName: String) {
        guard var progress = transferProgressState else {
            return
        }

        progress.itemName = itemName
        progress.completedBytes = min(progress.completedBytes + byteCount, progress.totalBytes)

        let now = Date()
        let shouldPublish = progress.totalBytes == 0
            || progress.completedBytes == progress.totalBytes
            || now.timeIntervalSince(progress.updatedAt) >= progressUpdateInterval

        transferProgressState = progress

        guard shouldPublish else {
            return
        }

        progress.updatedAt = now
        activeTransfer = progress
        uploadProgress = progress.fractionCompleted
        sftpStatusMessage = progress.statusText
    }

    private func completeTransfer(message: String) {
        if var progress = transferProgressState {
            progress.completedBytes = progress.totalBytes
            progress.updatedAt = Date()
            transferProgressState = progress
            activeTransfer = progress
            uploadProgress = 1
        }
        sftpStatusMessage = message
    }

    private func failTransfer(_ error: Error) {
        sftpStatusMessage = error.localizedDescription
        showUploadIndicator = false
        uploadProgress = 0
        transferProgressState = nil
        activeTransfer = nil
    }

    private func scheduleTransferDismissal() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            self.showUploadIndicator = false
            self.uploadProgress = 0
            self.transferProgressState = nil
            self.activeTransfer = nil
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

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Name cannot be empty or contain '/'."
        case .invalidPath:
            return "Path cannot be empty."
        }
    }
}

enum SFTPTransferKind: String, Sendable {
    case upload = "Uploading"
    case download = "Downloading"
}

struct SFTPTransferProgress: Equatable, Sendable {
    let kind: SFTPTransferKind
    var itemName: String
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
