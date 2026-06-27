import Foundation
import Combine
@preconcurrency import Citadel
@preconcurrency import NIOCore
internal import NIOSSH

@MainActor
final class TerminalSessionManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isShellActive = false
    @Published private(set) var didShellExit = false
    @Published private(set) var currentRemotePath = "/"
    @Published private(set) var remoteFiles: [RemoteFile] = []
    @Published var uploadProgress = 0.0
    @Published var showUploadIndicator = false
    @Published var statusMessage = "正在等待 SSH 连接建立..."
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

    deinit {
        shellTask?.cancel()
        inputContinuation?.finish()
    }

    func connect(host: String, port: Int = 22, user: String, auth: SSHAuthentication) async throws {
        try await disconnect()

        didShellExit = false
        statusMessage = "正在连接 \(user)@\(host):\(port)..."

        let authenticationMethod = try auth.makeCitadelMethod(username: user)
        let sshClient = try await SSHClient.connect(
            host: host,
            port: port,
            authenticationMethod: authenticationMethod,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )

        sshClient.onDisconnect { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
                self?.isShellActive = false
                self?.statusMessage = "SSH 连接已断开"
            }
        }

        self.client = sshClient
        self.sftp = try await sshClient.openSFTP()
        self.isConnected = true
        self.statusMessage = "SSH 已连接"

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
        statusMessage = "SSH 连接已关闭"
    }

    func fetchRemoteFiles(at path: String) async throws {
        guard let sftp else {
            return
        }

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
    }

    func uploadFile(localURL: URL) async throws {
        guard let sftp else {
            return
        }

        let shouldStopAccessing = localURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                localURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = localURL.lastPathComponent
        let destinationPath = remotePath(appending: fileName)
        let data = try Data(contentsOf: localURL)

        showUploadIndicator = true
        uploadProgress = 0

        try await sftp.withFile(filePath: destinationPath, flags: [.write, .create, .truncate]) { file in
            let chunkSize = 32_000
            var offset = 0

            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                let chunk = ByteBuffer(bytes: data[offset..<end])
                try await file.write(chunk, at: UInt64(offset))

                offset = end
                await MainActor.run {
                    self.uploadProgress = data.isEmpty ? 1 : Double(offset) / Double(data.count)
                }
            }
        }

        uploadProgress = 1
        try await fetchRemoteFiles(at: currentRemotePath)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            self.showUploadIndicator = false
            self.uploadProgress = 0
        }
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
            var didExitNormally = false

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
                didExitNormally = true
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self?.statusMessage = "SSH Shell 异常中断: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                let shouldNotifyExit = self?.shellSessionID == shellSessionID && didExitNormally
                if shouldNotifyExit {
                    self?.didShellExit = true
                }
                self?.isShellActive = false
                if shouldNotifyExit {
                    self?.onShellExit?()
                }
                self?.shellTask = nil
                self?.shellSessionID = nil
                self?.inputContinuation = nil
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
}
