//
//  ServerManagerView.swift
//  Velox
//
//  Created by yangxy on 2026/6/27.
//

import AppKit
import SwiftUI

// MARK: - 焦点与字段定义
private enum Field: Hashable {
    case name, host, port, username, password, privateKeyPath, passphrase
}

// MARK: - 主管理器视图
struct ServerManagerView: View {
    @ObservedObject var serverStore: ServerDirectoryStore
    let connectInCurrentWindow: @MainActor (ServerProfile, SSHAuthentication) -> Void
    let connectInNewWindow: @MainActor (ServerProfile, SSHAuthentication) -> Void

    @State private var selectedProfileID: UUID?
    @State private var selectedFolder = "Default"
    @State private var editorMode: EditorMode?
    @State private var pendingOpenProfile: ServerProfile?
    @State private var showsOpenChoice = false
    @State private var openingProfileIDs: Set<UUID> = []
    
    // 控制目录树文件夹的折叠/展开状态
    @State private var expandedFolders: [String: Bool] = [:]
    
    // 文件夹内联重命名的状态控制
    @State private var editingFolderName: String? = nil
    @State private var folderRenameBuffer: String = ""

    private let openPreferenceKey = "Velox.ServerOpenPreference.v1"

    enum EditorMode: Identifiable {
        case create(folder: String)
        case edit(ServerProfile)

        var id: String {
            switch self {
            case .create(let folder): return "create:\(folder)"
            case .edit(let profile):  return "edit:\(profile.id.uuidString)"
            }
        }
    }

    private var selectedProfile: ServerProfile? {
        guard let selectedProfileID else { return nil }
        return serverStore.profiles.first { $0.id == selectedProfileID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()
                .overlay(.white.opacity(0.06))

            serverTreeDirectory
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.052, green: 0.055, blue: 0.057),
                    Color(red: 0.035, green: 0.037, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(.white.opacity(0.9))
        // 顶层按键响应：如果选中的是普通节点，按 Delete 键删除
        .onDeleteCommand {
            if selectedProfileID != nil {
                deleteSelectedProfile()
            } else if selectedFolder != "Default" {
                deleteSelectedFolder()
            }
        }
        // 快捷键支持：选中文件夹时按回车键触发重命名
        .onKeyPress(.return) {
            if selectedProfileID == nil && editingFolderName == nil {
                startRenameFolder(selectedFolder)
                return .handled
            }
            return .ignored
        }
        .sheet(item: $editorMode) { mode in
            ServerProfileEditorSheet(
                mode: mode,
                folders: serverStore.folders,
                authSecretForProfile: { serverStore.authSecret(for: $0) },
                save: { profile, authSecret in
                    serverStore.save(profile, authSecret: authSecret)
                    selectedProfileID = profile.id
                    selectedFolder = profile.group
                },
                createFolder: { name in
                    serverStore.createFolder(named: name)
                }
            )
        }
        .confirmationDialog("Open SSH", isPresented: $showsOpenChoice, titleVisibility: .visible) {
            Button("Open in Current Window") {
                rememberOpenPreference("current")
                openPendingProfile(inNewWindow: false)
            }
            Button("Open in New Window") {
                rememberOpenPreference("new")
                openPendingProfile(inNewWindow: true)
            }
            Button("Cancel", role: .cancel) {
                pendingOpenProfile = nil
            }
        } message: {
            Text("Choose the default action when double-clicking a server.")
        }
    }

    // MARK: - 工具栏
    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Servers", systemImage: "server.rack")
                    .font(.system(size: 17, weight: .semibold))
                Text("Double-click a server to connect. Click a folder row to expand or collapse.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.44))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                managerButton("New Server", icon: "plus") {
                    editorMode = .create(folder: selectedFolder)
                }

                managerButton("New Folder", icon: "folder.badge.plus") {
                    createFolder()
                }

                Divider()
                    .frame(height: 20)
                    .overlay(.white.opacity(0.1))

                managerButton("Edit", icon: "pencil") {
                    if let selectedProfile { editorMode = .edit(selectedProfile) }
                }
                .disabled(selectedProfile == nil)

                managerButton("Clone", icon: "doc.on.doc") {
                    cloneSelectedProfile()
                }
                .disabled(selectedProfile == nil)

                managerButton("Delete", icon: "trash") {
                    if selectedProfile != nil {
                        deleteSelectedProfile()
                    } else {
                        deleteSelectedFolder()
                    }
                }
                .disabled(selectedProfile == nil && selectedFolder == "Default")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(Color.black.opacity(0.18))
    }

    // MARK: - 现代树状目录结构
    private var serverTreeDirectory: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(serverStore.profiles.count) saved \(serverStore.profiles.count == 1 ? "server" : "servers")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text(selectedProfile == nil ? "Folder selected" : "Server selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.34))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let groupedProfiles = Dictionary(grouping: serverStore.profiles, by: { $0.group })

                    if serverStore.profiles.isEmpty {
                        emptyState
                    }

                    ForEach(serverStore.folders, id: \.self) { folder in
                        let profiles = groupedProfiles[folder] ?? []
                        folderSection(folder: folder, profiles: profiles)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))

            Text("No server profiles yet")
                .font(.system(size: 15, weight: .semibold))

            Text("Create a server profile, group it in a folder, then double-click it to connect.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.48))

            Button {
                editorMode = .create(folder: selectedFolder)
            } label: {
                Label("New Server", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func folderSection(folder: String, profiles: [ServerProfile]) -> some View {
        let isExpanded = expandedFolders[folder, default: true]

        return VStack(alignment: .leading, spacing: 5) {
            folderHeader(folder: folder, count: profiles.count, isExpanded: isExpanded)

            if isExpanded {
                if profiles.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray")
                            .frame(width: 16)
                        Text("No servers in this folder")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.36))
                    .padding(.leading, 34)
                    .frame(height: 28)
                } else {
                    ForEach(profiles) { profile in
                        serverTreeRow(profile)
                            .padding(.leading, 26)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 文件夹头部样式 (带右键菜单与内联编辑)
    private func folderHeader(folder: String, count: Int, isExpanded: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
                .rotationEffect(isExpanded ? .degrees(90) : .degrees(0))
                .frame(width: 16, height: 16)

            Image(systemName: count == 0 ? "folder" : "folder.fill")
                .foregroundStyle(.accent.opacity(0.8))
                .font(.system(size: 14))
                .frame(width: 18)

            if editingFolderName == folder {
                TextField("", text: $folderRenameBuffer, onCommit: {
                    commitRenameFolder(oldName: folder)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .background(Color.blue.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: 220)
                .onTapGesture {}
            } else {
                Text(folder)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(.white.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .frame(height: 36)
        .background(
            selectedFolder == folder && selectedProfileID == nil ? Color.white.opacity(0.075) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .onTapGesture {
            selectedFolder = folder
            selectedProfileID = nil
            guard editingFolderName != folder else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                expandedFolders[folder, default: true].toggle()
            }
        }
        .contextMenu {
            Button {
                selectedFolder = folder
                selectedProfileID = nil
                editorMode = .create(folder: folder)
            } label: {
                Label("New Server Here", systemImage: "plus")
            }
            
            Divider()
            
            Button {
                startRenameFolder(folder)
            } label: {
                Label("Rename Folder", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                selectedFolder = folder
                selectedProfileID = nil
                deleteSelectedFolder()
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    // MARK: - 服务器节点样式
    private func serverTreeRow(_ profile: ServerProfile) -> some View {
        return HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(.cyan.opacity(0.85))
                .font(.system(size: 13))
                .frame(width: 16)

            Text(profile.name)
                .font(.system(size: 13, weight: .semibold))
                .layoutPriority(1)

            HStack(spacing: 4) {
                Text("\(profile.username)@\(profile.host)")
                Text(":\(profile.port)")
                    .foregroundStyle(.white.opacity(0.3))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.42))
            .lineLimit(1)

            Spacer(minLength: 0)

            if openingProfileIDs.contains(profile.id) {
                ProgressView().controlSize(.small)
            } else if profile.lastConnectedAt != nil {
                Circle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .help("Recently Connected")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            selectedProfileID == profile.id ? Color.blue.opacity(0.24) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedProfileID = profile.id
            selectedFolder = profile.group
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                requestOpen(profile)
            }
        )
        .contextMenu {
            Button {
                requestOpen(profile)
            } label: {
                Label("Connect", systemImage: "bolt.horizontal")
            }

            Divider()

            Button {
                editorMode = .edit(profile)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                selectedProfileID = profile.id
                cloneSelectedProfile()
            } label: {
                Label("Clone", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                deleteSelectedProfile()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func managerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(title)
    }

    // MARK: - 内部控制逻辑
    private func startRenameFolder(_ folder: String) {
        folderRenameBuffer = folder
        editingFolderName = folder
    }

    private func commitRenameFolder(oldName: String) {
        let trimmed = folderRenameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 核心修正 2：调用持久层进行文件夹改名，并重映射其下所有 Server 关联的 group
        if !trimmed.isEmpty && trimmed != oldName && !serverStore.folders.contains(trimmed) {
            serverStore.renameFolder(from: oldName, to: trimmed)
            selectedFolder = trimmed
        }
        editingFolderName = nil
    }

    private func createFolder() {
        let baseName = "New Folder"
        var candidate = baseName
        var suffix = 2
        while serverStore.folders.contains(candidate) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        selectedFolder = serverStore.createFolder(named: candidate)
        expandedFolders[selectedFolder] = true
        selectedProfileID = nil
        
        // 创建后自动切入重命名状态
        startRenameFolder(selectedFolder)
    }

    private func deleteSelectedFolder() {
        serverStore.deleteFolder(named: selectedFolder)
        selectedFolder = serverStore.folders.first ?? "Default"
        selectedProfileID = nil
    }

    private func cloneSelectedProfile() {
        guard let selectedProfile else { return }
        let cloned = ServerProfile(
            name: "\(selectedProfile.name) Copy",
            host: selectedProfile.host,
            port: selectedProfile.port,
            username: selectedProfile.username,
            group: selectedProfile.group,
            authenticationMethod: selectedProfile.authenticationMethod,
            privateKeyPath: selectedProfile.privateKeyPath
        )
        serverStore.save(cloned, authSecret: serverStore.authSecret(for: selectedProfile.id))
        selectedProfileID = cloned.id
    }

    private func deleteSelectedProfile() {
        guard let selectedProfile else { return }
        serverStore.delete(selectedProfile)
        selectedProfileID = nil
    }

    private func requestOpen(_ profile: ServerProfile) {
        guard !openingProfileIDs.contains(profile.id) else { return }

        switch UserDefaults.standard.string(forKey: openPreferenceKey) {
        case "current":
            openingProfileIDs.insert(profile.id)
            openProfile(profile, inNewWindow: false)
        case "new":
            openingProfileIDs.insert(profile.id)
            openProfile(profile, inNewWindow: true)
        default:
            pendingOpenProfile = profile
            showsOpenChoice = true
        }
    }

    private func rememberOpenPreference(_ preference: String) {
        UserDefaults.standard.set(preference, forKey: openPreferenceKey)
    }

    private func openPendingProfile(inNewWindow: Bool) {
        guard let pendingOpenProfile else { return }
        openProfile(pendingOpenProfile, inNewWindow: inNewWindow)
        self.pendingOpenProfile = nil
    }

    private func openProfile(_ profile: ServerProfile, inNewWindow: Bool) {
        if !openingProfileIDs.contains(profile.id) {
            openingProfileIDs.insert(profile.id)
        }

        let auth: SSHAuthentication
        do {
            auth = try serverStore.authentication(for: profile)
        } catch {
            print("Failed to load SSH authentication: \(error.localizedDescription)")
            openingProfileIDs.remove(profile.id)
            return
        }
        
        if inNewWindow {
            connectInNewWindow(profile, auth)
        } else {
            connectInCurrentWindow(profile, auth)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            openingProfileIDs.remove(profile.id)
        }
    }
}

// MARK: - 编辑/新建 Sheet 视图
private struct ServerProfileEditorSheet: View {
    let mode: ServerManagerView.EditorMode
    let folders: [String]
    let authSecretForProfile: (UUID) -> String
    let save: (ServerProfile, String) -> Void
    let createFolder: (String) -> String

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var folder = "Default"
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authenticationMethod: ServerAuthenticationMethod = .password
    @State private var authSecret = ""
    @State private var privateKeyPath = ""
    @State private var showsSecret = false

    @FocusState private var focusedField: Field?

    private let namePattern = #"^[\p{L}\p{N}][\p{L}\p{N}\s._-]{1,63}$"#
    private let hostPattern = #"^(([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?|((25[0-5]|2[0-4]\d|1?\d?\d)(\.|$)){4})$"#
    private let usernamePattern = #"^[A-Za-z0-9._-]{1,64}$"#
    private let privateKeyPattern = #"^(/[^/\0]+)+$"#
    private let passwordPattern = #"^.{1,1024}$"#
    private let passphrasePattern = #"^.{0,1024}$"#

    private var canSave: Bool {
        validationErrors.isEmpty
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if !matches(name, pattern: namePattern) {
            errors.append("Profile name must be 2-64 characters and may contain letters, numbers, spaces, dots, underscores, and hyphens.")
        }
        if !matches(host, pattern: hostPattern) {
            errors.append("Host must be a valid hostname or IPv4 address.")
        }
        if !(1...65535).contains(Int(port) ?? 0) {
            errors.append("Port must be a number from 1 to 65535.")
        }
        if !matches(username, pattern: usernamePattern) {
            errors.append("Username may contain letters, numbers, dots, underscores, and hyphens.")
        }
        switch authenticationMethod {
        case .password:
            if !matches(authSecret, pattern: passwordPattern) {
                errors.append("Password is required and must be 1024 characters or fewer.")
            }
        case .rsaPrivateKey:
            if !matches(privateKeyPath, pattern: privateKeyPattern) || !FileManager.default.fileExists(atPath: privateKeyPath) {
                errors.append("Private key path must point to an existing local file.")
            }
        case .ed25519PrivateKey:
            if !matches(privateKeyPath, pattern: privateKeyPattern) || !FileManager.default.fileExists(atPath: privateKeyPath) {
                errors.append("Private key path must point to an existing local file.")
            }
            if !matches(authSecret, pattern: passphrasePattern) {
                errors.append("Passphrase must be 1024 characters or fewer.")
            }
        }
        return errors
    }

    private var authSecretToSave: String {
        authenticationMethod == .rsaPrivateKey ? "" : authSecret
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text("Use clear names and valid connection settings. Secrets are stored in Keychain.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 16) {
                settingsSection("Profile") {
                    validatedField(
                        .name,
                        title: "Name",
                        icon: "tag",
                        placeholder: "Production SSH",
                        text: $name,
                        pattern: namePattern,
                        help: "2-64 characters. Letters, numbers, spaces, dots, underscores, and hyphens are allowed."
                    )

                    readOnlyFolderField
                }

                settingsSection("Connection") {
                    HStack(spacing: 12) {
                        validatedField(
                            .host,
                            title: "Host",
                            icon: "network",
                            placeholder: "example.com or 192.168.1.10",
                            text: $host,
                            pattern: hostPattern,
                            help: "Enter a hostname, domain name, or IPv4 address."
                        )

                        validatedField(
                            .port,
                            title: "Port",
                            icon: "number",
                            placeholder: "22",
                            text: $port,
                            validator: { (1...65535).contains(Int($0) ?? 0) },
                            help: "TCP port from 1 to 65535."
                        )
                        .frame(width: 132)
                    }

                    validatedField(
                        .username,
                        title: "Username",
                        icon: "person",
                        placeholder: "deploy",
                        text: $username,
                        pattern: usernamePattern,
                        help: "1-64 characters. Letters, numbers, dots, underscores, and hyphens are allowed."
                    )
                }

                settingsSection("Authentication") {
                    Picker("Method", selection: $authenticationMethod) {
                        ForEach(ServerAuthenticationMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Choose password authentication or a private key certificate.")
                    .onChange(of: authenticationMethod) { _, _ in
                        authSecret = ""
                    }

                    authenticationFields
                }
            }

            if !validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(validationErrors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange.opacity(0.86))
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    save(makeProfile(with: folder), authSecretToSave)
                    dismiss()
                } label: {
                    Text("Save Profile")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                switch mode {
                case .create: focusedField = .name
                case .edit: focusedField = .host
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .create: return "New Server Connection"
        case .edit:   return "Edit Server Profile"
        }
    }

    private var icon: String {
        switch mode {
        case .create: return "plus.circle.fill"
        case .edit:   return "pencil.circle.fill"
        }
    }

    private var passwordField: some View {
        secretField(
            title: "Password",
            icon: "key",
            placeholder: "Required",
            focus: .password,
            validator: { matches($0, pattern: passwordPattern) },
            help: "Required for password authentication. 1-1024 characters. Stored in Keychain."
        )
    }

    @ViewBuilder
    private var authenticationFields: some View {
        switch authenticationMethod {
        case .password:
            passwordField
        case .rsaPrivateKey, .ed25519PrivateKey:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    validatedField(
                        .privateKeyPath,
                        title: "Private Key",
                        icon: "doc.badge.key",
                        placeholder: "/Users/me/.ssh/id_ed25519",
                        text: $privateKeyPath,
                        validator: { matches($0, pattern: privateKeyPattern) && FileManager.default.fileExists(atPath: $0) },
                        help: "Absolute path to an existing private key file. The file content is read only when connecting."
                    )

                    Button {
                        choosePrivateKey()
                    } label: {
                        Image(systemName: "folder")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .help("Choose a private key file")
                }

                if authenticationMethod == .ed25519PrivateKey {
                    secretField(
                        title: "Passphrase",
                        icon: "lock",
                        placeholder: "Optional",
                        focus: .passphrase,
                        validator: { matches($0, pattern: passphrasePattern) },
                        help: "Optional Ed25519 private key passphrase. Up to 1024 characters. Stored in Keychain."
                    )
                }
            }
        }
    }

    private var readOnlyFolderField: some View {
        return HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                Text(folder)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .managerField(isValid: true)
        .help("Folder is controlled by the selected directory. Move profiles by editing folders in the server list.")
    }

    private func secretField(
        title: String,
        icon: String,
        placeholder: String,
        focus: Field,
        validator: @escaping (String) -> Bool,
        help: String
    ) -> some View {
        let isValid = validator(authSecret)

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                Group {
                    if showsSecret {
                        TextField(placeholder, text: $authSecret)
                    } else {
                        SecureField(placeholder, text: $authSecret)
                    }
                }
                .focused($focusedField, equals: focus)
                .textFieldStyle(.plain)
            }

            Button {
                showsSecret.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    focusedField = focus
                }
            } label: {
                Image(systemName: showsSecret ? "eye.slash" : "eye")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(showsSecret ? "Hide secret" : "Show secret")
        }
        .managerField(isValid: isValid)
        .help(help)
    }

    private func validatedField(
        _ fieldType: Field,
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        pattern: String? = nil,
        validator: ((String) -> Bool)? = nil,
        help: String
    ) -> some View {
        let isValid = validator?(text.wrappedValue) ?? (pattern.map { matches(text.wrappedValue, pattern: $0) } ?? true)

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: fieldType)
                    .textFieldStyle(.plain)
            }

            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isValid ? Color.green.opacity(0.7) : Color.orange.opacity(0.85))
        }
        .managerField(isValid: isValid)
        .help(help)
    }

    private func load() {
        switch mode {
        case .create(let folder):
            self.folder = folder
        case .edit(let profile):
            name = profile.name
            folder = profile.group
            host = profile.host
            port = "\(profile.port)"
            username = profile.username
            authenticationMethod = profile.authenticationMethod
            privateKeyPath = profile.privateKeyPath
            authSecret = authSecretForProfile(profile.id)
        }
    }

    private func makeProfile(with finalFolder: String) -> ServerProfile {
        switch mode {
        case .create:
            return ServerProfile(
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                group: finalFolder,
                authenticationMethod: authenticationMethod,
                privateKeyPath: privateKeyPath
            )
        case .edit(let profile):
            return ServerProfile(
                id: profile.id,
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                group: finalFolder,
                authenticationMethod: authenticationMethod,
                privateKeyPath: privateKeyPath,
                lastConnectedAt: profile.lastConnectedAt
            )
        }
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - View 独占样式扩展
private extension View {
    func managerField(isValid: Bool = true) -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isValid ? .white.opacity(0.1) : .orange.opacity(0.5), lineWidth: 1)
            }
    }
}
