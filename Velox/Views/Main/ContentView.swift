//
//  ContentView.swift
//  Velox
//
//  Created by yangxy on 2026/6/28.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 主视图
struct ContentView: View {
    @EnvironmentObject private var settings: VeloxSettings
    @StateObject private var sessionManager = TerminalSessionManager()
    @StateObject private var serverStore = ServerDirectoryStore()

    @State private var selectedProfileID: UUID?
    @State private var isDropTargeted = false
    @State private var showsSFTPPane = false
    @State private var serverManagerWindowController: ServerManagerWindowController?
    @State private var window: NSWindow?
    @State private var didApplyInitialWindowSettings = false

    var body: some View {
        ZStack {
            appBackground

            if sessionManager.isConnected {
                RemoteShellSplitView(sessionManager: sessionManager, showsFilePane: $showsSFTPPane)
            } else {
                LocalTerminalViewBridge(settings: settings)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: settings.terminalBackgroundColor))
            }

            uploadOverlay
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showsSFTPPane)
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(.white.opacity(0.24), lineWidth: 2)
                    .background(Color.white.opacity(0.05))
            }
        }
        // 升级为强类型现代 Drop 接收器，避免解析 NSItemProvider 的异步线程隐患
        .dropDestination(for: URL.self) { urls, _ in
            handleDroppedURLs(urls)
        } isTargeted: { isDropTargeted = $0 }
        .onChange(of: sessionManager.isConnected) { _, isConnected in
            showsSFTPPane = isConnected
            applyMainWindowSettings()
        }
        .onChange(of: sessionManager.currentRemotePath) { _, _ in
            applyMainWindowSettings()
        }
        .onChange(of: sessionManager.remoteTitlePrefix) { _, _ in
            applyMainWindowSettings()
        }
        .background(WindowAccessor { newWindow in
            window = newWindow
            applyMainWindowSettings(resize: !didApplyInitialWindowSettings)
            didApplyInitialWindowSettings = true
        })
        .focusedSceneValue(\.openServerManagerAction, {
            openServerManager()
        })
        .focusedSceneValue(\.openRemoteFolderAction, sessionManager.isConnected ? {
            showsSFTPPane = true
        } : nil)
        .onAppear {
            // 使用 [weak window] 破除循环引用，防止内存泄漏
            sessionManager.onShellExit = { [weak window] in
                window?.close()
            }
        }
        .onChange(of: settings.appearanceMode) { _, _ in
            applyMainWindowSettings()
        }
        .onChange(of: settings.isTransparent) { _, _ in
            applyMainWindowSettings()
        }
        .onChange(of: settings.transparency) { _, _ in
            applyMainWindowSettings()
        }
        .onChange(of: settings.defaultWindowWidth) { _, _ in
            applyMainWindowSettings(resize: true)
        }
        .onChange(of: settings.defaultWindowHeight) { _, _ in
            applyMainWindowSettings(resize: true)
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .frame(minWidth: 720, minHeight: 420)
    }

    private func applyMainWindowSettings(resize: Bool = false) {
        settings.apply(to: window, resize: resize)
        VeloxWindowStyler.applyTerminalWindowStyle(to: window, title: chromeTitle, settings: settings)
    }

    private var chromeTitle: String {
        if sessionManager.isConnected, let prefix = sessionManager.remoteTitlePrefix {
            return "\(prefix):\(sessionManager.currentRemotePath)"
        }

        return "\(NSUserName())@\(localHostName):\(localWorkingDirectory)"
    }

    private var localHostName: String {
        Host.current().localizedName ?? "localhost"
    }

    private var localWorkingDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = FileManager.default.currentDirectoryPath
        if path == home {
            return "~"
        }

        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }

        return path
    }

    private var appBackground: some View {
        LinearGradient(
            colors: settings.backgroundGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var uploadOverlay: some View {
        if sessionManager.showUploadIndicator {
            VStack {
                ProgressView(value: sessionManager.uploadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)

                Spacer()
            }
        }
    }

    private func openServerManager() {
        if serverManagerWindowController == nil {
            serverManagerWindowController = ServerManagerWindowController()
        }

        serverManagerWindowController?.open(store: serverStore) { profile, auth in
            Task {
                do {
                    try await sessionManager.connect(
                        host: profile.host,
                        port: profile.port,
                        user: profile.username,
                        auth: auth
                    )
                    serverStore.markConnected(profile)
                } catch {
                    // 处理或向外抛出连接错误
                    print("Connection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleDroppedURLs(_ urls: [URL]) -> Bool {
        guard sessionManager.isConnected else { return false }
        Task { @MainActor in
            for url in urls {
                try? await sessionManager.uploadFile(localURL: url)
            }
        }
        return true
    }
}

// MARK: - 抽离出来的独立服务器目录与配置面板 Component
struct ServerDirectoryPanel: View {
    @ObservedObject var serverStore: ServerDirectoryStore
    @ObservedObject var sessionManager: TerminalSessionManager
    @Binding var selectedProfileID: UUID?
    
    @Environment(\.dismiss) private var dismiss // 用于控制面板隐藏（视具体交互而定）

    // 收拢所有表单局部状态，打字时不再引发主视图无用重绘
    @State private var profileName = ""
    @State private var group = "Default"
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showsPassword = false
    
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            serverList
                .frame(width: 260)

            Divider()
                .overlay(.white.opacity(0.1))

            serverEditor
                .frame(width: 430)
        }
        .frame(height: 500)
        .foregroundStyle(.white.opacity(0.9))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.36), radius: 28, y: 16)
        .onChange(of: selectedProfileID) { _, newValue in
            loadProfile(id: newValue)
        }
    }

    private var serverList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Servers", systemImage: "server.rack")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                Button {
                    createFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Create Folder")

                Button {
                    newProfile()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add Server")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if serverStore.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No servers")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add a profile, then connect with one click.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .padding(16)
                    }

                    ForEach(serverStore.folders, id: \.self) { folder in
                        let profiles = serverStore.profiles.filter { $0.group == folder }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Image(systemName: profiles.isEmpty ? "folder" : "folder.fill")
                                    .foregroundStyle(.yellow.opacity(0.86))
                                    .frame(width: 16)
                                Text(folder)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.52))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)

                            ForEach(profiles) { profile in
                                Button {
                                    selectedProfileID = profile.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "terminal")
                                            .foregroundStyle(.cyan.opacity(0.84))
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .lineLimit(1)
                                            HStack(spacing: 5) {
                                                Image(systemName: "person")
                                                Text("\(profile.username)@\(profile.host):\(profile.port)")
                                            }
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.48))
                                            .lineLimit(1)
                                        }

                                        Spacer(minLength: 0)

                                        if profile.lastConnectedAt != nil {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green.opacity(0.8))
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 50)
                                    .background(selectedProfileID == profile.id ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        deleteSelected(profile)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private var serverEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(selectedProfileID == nil ? "New Server" : "Server Profile", systemImage: selectedProfileID == nil ? "plus.circle" : "server.rack")
                        .font(.system(size: 17, weight: .semibold))
                    Text(host.isEmpty ? "Create or update a connection profile." : "\(username)@\(host):\(port)")
                        .font(.system(size: 12, design: host.isEmpty ? .default : .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    // 执行隐藏/关闭行为
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 11) {
                serverField(icon: "tag", placeholder: "Name", text: $profileName)

                HStack(spacing: 10) {
                    serverField(icon: "folder", placeholder: "Folder", text: $group)

                    Button {
                        createFolder()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .frame(width: 28)
                    }
                    .buttonStyle(.bordered)
                    .help("Create Folder")
                }

                HStack(spacing: 10) {
                    serverField(icon: "network", placeholder: "Host", text: $host)
                    serverField(icon: "number", placeholder: "22", text: $port)
                        .frame(width: 82)
                }

                serverField(icon: "person", placeholder: "User", text: $username)

                passwordField
            }

            if let connectionError {
                Label(connectionError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    saveCurrentProfile()
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!canSaveProfile)

                Button {
                    Task { await connectCurrentProfile() }
                } label: {
                    Label(isConnecting ? "Connecting" : "Connect", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveProfile || isConnecting)

                Button(role: .destructive) {
                    if let profile = selectedProfile {
                        deleteSelected(profile)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(selectedProfile == nil)
            }
        }
        .padding(16)
    }

    private var passwordField: some View {
        HStack(spacing: 9) {
            Image(systemName: "key")
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 18)

            Group {
                if showsPassword {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .focused($isPasswordFocused)
            .textFieldStyle(.plain)

            Button {
                showsPassword.toggle()
                // 解决原生重绘组件时丢失焦点的体验缺陷
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isPasswordFocused = true
                }
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.58))
            .help(showsPassword ? "Hide Password" : "Show Password")
        }
        .veloxField()
    }

    private func serverField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 18)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
        .veloxField()
    }

    // MARK: - 内部业务辅助逻辑
    private var selectedProfile: ServerProfile? {
        guard let selectedProfileID else { return nil }
        return serverStore.profiles.first { $0.id == selectedProfileID }
    }

    private var canSaveProfile: Bool {
        !profileName.isEmpty && !host.isEmpty && !username.isEmpty && !password.isEmpty
    }

    private func newProfile() {
        selectedProfileID = nil
        profileName = ""
        group = serverStore.folders.first ?? "Default"
        host = ""
        port = "22"
        username = ""
        password = ""
        showsPassword = false
        connectionError = nil
    }

    private func createFolder() {
        let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "New Folder" : trimmed
        var candidate = baseName
        var suffix = 2

        while serverStore.folders.contains(candidate) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }

        group = serverStore.createFolder(named: candidate)
    }

    private func loadProfile(id: UUID?) {
        guard let id, let profile = serverStore.profiles.first(where: { $0.id == id }) else { return }
        profileName = profile.name
        group = profile.group
        host = profile.host
        port = "\(profile.port)"
        username = profile.username
        password = serverStore.password(for: profile.id)
        connectionError = nil
    }

    @discardableResult
    private func saveCurrentProfile() -> ServerProfile? {
        guard canSaveProfile else { return nil }

        let profile = ServerProfile(
            id: selectedProfileID ?? UUID(),
            name: profileName,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            group: group.isEmpty ? "Default" : group
        )

        serverStore.save(profile, password: password)
        selectedProfileID = profile.id
        return profile
    }

    private func deleteSelected(_ profile: ServerProfile) {
        serverStore.delete(profile)
        if selectedProfileID == profile.id {
            newProfile()
        }
    }

    private func connectCurrentProfile() async {
        guard let profile = saveCurrentProfile() else { return }

        isConnecting = true
        connectionError = nil

        defer { isConnecting = false }

        do {
            try await sessionManager.connect(
                host: profile.host,
                port: profile.port,
                user: profile.username,
                auth: .password(password)
            )
            serverStore.markConnected(profile)
        } catch {
            connectionError = error.localizedDescription
        }
    }
}

// MARK: - 全局 View 样式扩展
private extension View {
    func veloxField() -> some View {
        self
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}
