//
//  ContentView.swift
//  Velox
//
//  Created by yangxy on 2026/6/28.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var sessionManager = TerminalSessionManager()
    @StateObject private var serverStore = ServerDirectoryStore()

    @State private var selectedProfileID: UUID?
    @State private var profileName = ""
    @State private var group = "Default"
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var isDropTargeted = false
    @State private var showsServerDirectory = false
    @State private var showsSFTPPane = false
    @State private var showsPassword = false
    @State private var serverManagerWindowController: ServerManagerWindowController?
    @State private var window: NSWindow?

    var body: some View {
        ZStack {
            appBackground

            if sessionManager.isConnected {
                RemoteShellSplitView(sessionManager: sessionManager, showsFilePane: $showsSFTPPane)
            } else {
                LocalTerminalViewBridge()
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
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: uploadDroppedFiles)
        .onChange(of: selectedProfileID) { _, newValue in
            loadProfile(id: newValue)
        }
        .onChange(of: sessionManager.isConnected) { _, isConnected in
            showsSFTPPane = isConnected
        }
        .background(WindowAccessor { window = $0 })
        .focusedSceneValue(\.openServerManagerAction, {
            openServerManager()
        })
        .focusedSceneValue(\.openRemoteFolderAction, sessionManager.isConnected ? {
            showsSFTPPane = true
        } : nil)
        .onAppear {
            sessionManager.onShellExit = {
                window?.close()
            }
        }
        .frame(minWidth: 940, minHeight: 580)
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.038, blue: 0.04),
                Color(red: 0.055, green: 0.058, blue: 0.056)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label("Velox", systemImage: "terminal")
                .font(.system(size: 13, weight: .semibold))

            statusPill

            Spacer(minLength: 24)

            Button {
                openServerManager()
            } label: {
                Image(systemName: "server.rack")
            }
            .help("Servers")
            .keyboardShortcut("p", modifiers: .command)

            Button {
                showsSFTPPane.toggle()
            } label: {
                Image(systemName: "folder")
            }
            .help("SFTP")
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!sessionManager.isConnected)

            Button {
                Task { try? await sessionManager.disconnect() }
            } label: {
                Image(systemName: "power")
            }
            .help("Disconnect SSH")
            .disabled(!sessionManager.isConnected)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionManager.isConnected ? Color.green : Color.cyan)
                .frame(width: 7, height: 7)

            Text(sessionManager.isConnected ? sessionManager.statusMessage : "Local shell")
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.74))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.24), in: Capsule())
    }

    private var serverDirectoryPanel: some View {
        HStack(spacing: 0) {
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

                serverList
            }
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
    }

    private var serverList: some View {
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
                    showsServerDirectory = false
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

    private var sftpPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("SFTP", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    Task { try? await sessionManager.fetchRemoteFiles(at: sessionManager.currentRemotePath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    showsSFTPPane = false
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Text(sessionManager.currentRemotePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
                .overlay(.white.opacity(0.08))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sessionManager.remoteFiles) { file in
                        HStack(spacing: 9) {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(file.isDirectory ? .yellow.opacity(0.82) : .white.opacity(0.56))
                                .frame(width: 16)

                            Text(file.name)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(width: 1)
        }
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

    private var selectedProfile: ServerProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return serverStore.profiles.first { $0.id == selectedProfileID }
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
            .textFieldStyle(.plain)

            Button {
                showsPassword.toggle()
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
        guard let id, let profile = serverStore.profiles.first(where: { $0.id == id }) else {
            return
        }

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
        guard canSaveProfile else {
            return nil
        }

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
        guard let profile = saveCurrentProfile() else {
            return
        }

        isConnecting = true
        connectionError = nil

        defer {
            isConnecting = false
        }

        do {
            try await sessionManager.connect(
                host: profile.host,
                port: profile.port,
                user: profile.username,
                auth: .password(password)
            )
            serverStore.markConnected(profile)
            showsServerDirectory = false
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func connect(profile: ServerProfile, password: String) async {
        connectionError = nil

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

    private func openServerManager() {
        if serverManagerWindowController == nil {
            serverManagerWindowController = ServerManagerWindowController()
        }

        serverManagerWindowController?.open(store: serverStore) { profile, password in
            Task {
                await connect(profile: profile, password: password)
            }
        }
    }

    private func uploadDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard sessionManager.isConnected else {
            return false
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadDataRepresentation(for: .fileURL) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    try? await sessionManager.uploadFile(localURL: url)
                }
            }
        }

        return true
    }
}

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
