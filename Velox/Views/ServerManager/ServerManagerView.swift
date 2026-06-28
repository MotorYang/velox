//
//  ServerManagerView.swift
//  Velox
//
//  Created by yangxy on 2026/6/27.
//

import SwiftUI

// MARK: - 焦点与字段定义
private enum Field: Hashable {
    case name, folder, host, port, username, password
}

// MARK: - 主管理器视图
struct ServerManagerView: View {
    @ObservedObject var serverStore: ServerDirectoryStore
    let connectInCurrentWindow: @MainActor (ServerProfile, String) -> Void
    let connectInNewWindow: @MainActor (ServerProfile, String) -> Void

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
        .frame(minWidth: 740, minHeight: 540)
        .background(Color(red: 0.045, green: 0.048, blue: 0.05))
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
                passwordForProfile: { serverStore.password(for: $0) },
                save: { profile, password in
                    serverStore.save(profile, password: password)
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
        HStack(spacing: 6) {
            managerButton("New", icon: "plus.circle") {
                editorMode = .create(folder: selectedFolder)
            }

            managerButton("Edit", icon: "pencil") {
                if let selectedProfile { editorMode = .edit(selectedProfile) }
            }
            .disabled(selectedProfile == nil)

            managerButton("Clone", icon: "doc.on.doc") {
                cloneSelectedProfile()
            }
            .disabled(selectedProfile == nil)

            managerButton("Delete", icon: "trash") {
                deleteSelectedProfile()
            }
            .disabled(selectedProfile == nil)

            Divider()
                .frame(height: 16)
                .overlay(.white.opacity(0.1))

            managerButton("New Folder", icon: "folder.badge.plus") {
                createFolder()
            }

            managerButton("Delete Folder", icon: "folder.badge.minus") {
                deleteSelectedFolder()
            }
            .disabled(selectedFolder == "Default")

            Spacer(minLength: 0)

            Label("\(serverStore.profiles.count) Servers", systemImage: "server.rack")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    // MARK: - 现代树状目录结构
    private var serverTreeDirectory: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let groupedProfiles = Dictionary(grouping: serverStore.profiles, by: { $0.group })

                ForEach(serverStore.folders, id: \.self) { folder in
                    let profiles = groupedProfiles[folder] ?? []
                    let isExpanded = Binding<Bool>(
                        get: { expandedFolders[folder, default: true] },
                        set: { expandedFolders[folder] = $0 }
                    )
                    
                    DisclosureGroup(isExpanded: isExpanded) {
                        if profiles.isEmpty {
                            Text("Empty folder")
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(.white.opacity(0.3))
                                .padding(.leading, 24)
                                .frame(height: 24)
                        } else {
                            ForEach(profiles) { profile in
                                serverTreeRow(profile)
                                    .padding(.leading, 12)
                            }
                        }
                    } label: {
                        folderHeader(folder: folder, count: profiles.count)
                    }
                    .disclosureGroupStyle(VeloxDisclosureStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 文件夹头部样式 (带右键菜单与内联编辑)
    private func folderHeader(folder: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: count == 0 ? "folder" : "folder.fill")
                .foregroundStyle(.yellow.opacity(0.8))
                .font(.system(size: 13))

            if editingFolderName == folder {
                // 就地无缝重命名输入框
                TextField("", text: $folderRenameBuffer, onCommit: {
                    commitRenameFolder(oldName: folder)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(Color.blue.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                .frame(maxWidth: 180)
                // 拦截点击事件，防止输入时触发折叠
                .onTapGesture {}
            } else {
                Text(folder)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 5)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
        .contentShape(Rectangle())
        .frame(height: 28)
        .background(
            selectedFolder == folder && selectedProfileID == nil ? Color.white.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .onTapGesture {
            selectedFolder = folder
            selectedProfileID = nil
        }
        .contextMenu {
            Button("New Server Here") {
                selectedFolder = folder
                selectedProfileID = nil
                editorMode = .create(folder: folder)
            }
            
            Divider()
            
            Button("Rename Folder") {
                startRenameFolder(folder)
            }
            
            Button("Delete Folder", role: .destructive) {
                selectedFolder = folder
                selectedProfileID = nil
                deleteSelectedFolder()
            }
        }
    }

    // MARK: - 服务器节点样式
    private func serverTreeRow(_ profile: ServerProfile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.cyan.opacity(0.85))
                .font(.system(size: 12))
                .frame(width: 14)

            Text(profile.name)
                .font(.system(size: 13, weight: .medium))
                .layoutPriority(1)

            HStack(spacing: 4) {
                Text("\(profile.username)@\(profile.host)")
                Text(":\(profile.port)")
                    .foregroundStyle(.white.opacity(0.3))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
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
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            selectedProfileID == profile.id ? Color.blue.opacity(0.25) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
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
            Button("Connect") { requestOpen(profile) }
            Divider()
            Button("Edit") { editorMode = .edit(profile) }
            Button("Clone") { selectedProfileID = profile.id; cloneSelectedProfile() }
            Button("Delete", role: .destructive) { deleteSelectedProfile() }
        }
    }

    private func managerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
            group: selectedProfile.group
        )
        serverStore.save(cloned, password: serverStore.password(for: selectedProfile.id))
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
            openProfile(profile, password: serverStore.password(for: profile.id), inNewWindow: false)
        case "new":
            openingProfileIDs.insert(profile.id)
            openProfile(profile, password: serverStore.password(for: profile.id), inNewWindow: true)
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
        let password = serverStore.password(for: pendingOpenProfile.id)
        openProfile(pendingOpenProfile, password: password, inNewWindow: inNewWindow)
        self.pendingOpenProfile = nil
    }

    private func openProfile(_ profile: ServerProfile, password: String, inNewWindow: Bool) {
        if !openingProfileIDs.contains(profile.id) {
            openingProfileIDs.insert(profile.id)
        }
        
        if inNewWindow {
            connectInNewWindow(profile, password)
        } else {
            connectInCurrentWindow(profile, password)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            openingProfileIDs.remove(profile.id)
        }
    }
}

// MARK: - 自定义紧凑型树状折叠样式
struct VeloxDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .rotationEffect(configuration.isExpanded ? .degrees(90) : .degrees(0))
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isExpanded)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            configuration.isExpanded.toggle()
                        }
                    }
                    .frame(width: 12, height: 12)

                configuration.label
            }
            
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 编辑/新建 Sheet 视图
private struct ServerProfileEditorSheet: View {
    let mode: ServerManagerView.EditorMode
    let folders: [String]
    let passwordForProfile: (UUID) -> String
    let save: (ServerProfile, String) -> Void
    let createFolder: (String) -> String

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var folder = "Default"
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var showsPassword = false

    @FocusState private var focusedField: Field?

    private var canSave: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .bold))

            VStack(spacing: 12) {
                field(.name, icon: "tag", placeholder: "Profile Name", text: $name)
                field(.folder, icon: "folder", placeholder: "Folder / Group", text: $folder)

                HStack(spacing: 12) {
                    field(.host, icon: "network", placeholder: "Host", text: $host)
                    field(.port, icon: "number", placeholder: "22", text: $port)
                        .frame(width: 90)
                }

                field(.username, icon: "person", placeholder: "Username", text: $username)
                passwordField
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    let finalFolder = createFolder(folder)
                    save(makeProfile(with: finalFolder), password)
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
        .padding(20)
        .frame(width: 420)
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
        HStack(spacing: 9) {
            Image(systemName: "key")
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 16)

            Group {
                if showsPassword {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .focused($focusedField, equals: .password)
            .textFieldStyle(.plain)

            Button {
                showsPassword.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    focusedField = .password
                }
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .managerField()
    }

    private func field(_ fieldType: Field, icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 16)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
        .focused($focusedField, equals: fieldType)
        .managerField()
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
            password = passwordForProfile(profile.id)
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
                group: finalFolder
            )
        case .edit(let profile):
            return ServerProfile(
                id: profile.id,
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                group: finalFolder,
                lastConnectedAt: profile.lastConnectedAt
            )
        }
    }
}

// MARK: - View 独占样式扩展
private extension View {
    func managerField() -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
    }
}
