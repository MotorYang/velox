import SwiftUI

struct ServerManagerView: View {
    @ObservedObject var serverStore: ServerDirectoryStore
    let connectInCurrentWindow: @MainActor (ServerProfile, String) -> Void
    let connectInNewWindow: @MainActor (ServerProfile, String) -> Void

    @State private var selectedProfileID: UUID?
    @State private var selectedFolder = "Default"
    @State private var editorMode: EditorMode?
    @State private var pendingOpenProfile: ServerProfile?
    @State private var pendingOpenPassword = ""
    @State private var showsOpenChoice = false
    @State private var openingProfileIDs: Set<UUID> = []

    private let openPreferenceKey = "Velox.ServerOpenPreference.v1"

    enum EditorMode: Identifiable {
        case create(folder: String)
        case edit(ServerProfile)

        var id: String {
            switch self {
            case .create(let folder):
                return "create:\(folder)"
            case .edit(let profile):
                return "edit:\(profile.id.uuidString)"
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
                .overlay(.white.opacity(0.08))

            serverDirectory
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Color(red: 0.045, green: 0.048, blue: 0.05))
        .foregroundStyle(.white.opacity(0.9))
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
            Button("当前窗口打开") {
                rememberOpenPreference("current")
                openPendingProfile(inNewWindow: false)
            }

            Button("新建窗口打开") {
                rememberOpenPreference("new")
                openPendingProfile(inNewWindow: true)
            }

            Button("取消", role: .cancel) {
                pendingOpenProfile = nil
                pendingOpenPassword = ""
            }
        } message: {
            Text("选择双击服务器后的默认打开方式。")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            managerButton("新建", icon: "plus.circle") {
                editorMode = .create(folder: selectedFolder)
            }

            managerButton("编辑", icon: "pencil") {
                if let selectedProfile {
                    editorMode = .edit(selectedProfile)
                }
            }
            .disabled(selectedProfile == nil)

            managerButton("克隆", icon: "doc.on.doc") {
                cloneSelectedProfile()
            }
            .disabled(selectedProfile == nil)

            managerButton("删除", icon: "trash") {
                deleteSelectedProfile()
            }
            .disabled(selectedProfile == nil)

            Divider()
                .frame(height: 24)
                .overlay(.white.opacity(0.12))

            managerButton("创建文件夹", icon: "folder.badge.plus") {
                createFolder()
            }

            managerButton("删除文件夹", icon: "folder.badge.minus") {
                deleteSelectedFolder()
            }
            .disabled(selectedFolder == "Default")

            Spacer(minLength: 0)

            Label("\(serverStore.profiles.count)", systemImage: "server.rack")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }

    private var serverDirectory: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(serverStore.folders, id: \.self) { folder in
                    folderSection(folder)
                }
            }
            .padding(14)
        }
    }

    private func folderSection(_ folder: String) -> some View {
        let profiles = serverStore.profiles.filter { $0.group == folder }

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                selectedFolder = folder
                selectedProfileID = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: profiles.isEmpty ? "folder" : "folder.fill")
                        .foregroundStyle(.yellow.opacity(0.86))
                        .frame(width: 18)

                    Text(folder)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Text("\(profiles.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(selectedFolder == folder && selectedProfileID == nil ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            ForEach(profiles) { profile in
                serverRow(profile)
            }
        }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(.cyan.opacity(0.84))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(profile.username, systemImage: "person")
                    Label(profile.host, systemImage: "network")
                    Label("\(profile.port)", systemImage: "number")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if openingProfileIDs.contains(profile.id) {
                ProgressView()
                    .controlSize(.small)
            } else if profile.lastConnectedAt != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(selectedProfileID == profile.id ? .white.opacity(0.1) : .black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            requestOpen(profile)
        }
        .onTapGesture(count: 1) {
            selectedProfileID = profile.id
            selectedFolder = profile.group
        }
    }

    private func managerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
        selectedProfileID = nil
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
        guard !openingProfileIDs.contains(profile.id) else {
            return
        }

        switch UserDefaults.standard.string(forKey: openPreferenceKey) {
        case "current":
            openingProfileIDs.insert(profile.id)
            let password = serverStore.password(for: profile.id)
            openProfile(profile, password: password, inNewWindow: false)
        case "new":
            openingProfileIDs.insert(profile.id)
            let password = serverStore.password(for: profile.id)
            openProfile(profile, password: password, inNewWindow: true)
        default:
            pendingOpenProfile = profile
            pendingOpenPassword = ""
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
        pendingOpenPassword = ""
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
            try? await Task.sleep(for: .seconds(1))
            openingProfileIDs.remove(profile.id)
        }
    }
}

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

    private var canSave: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .semibold))

            VStack(spacing: 10) {
                field("tag", "Name", text: $name)
                field("folder", "Folder", text: $folder)

                HStack(spacing: 10) {
                    field("network", "Host", text: $host)
                    field("number", "22", text: $port)
                        .frame(width: 100)
                }

                field("person", "User", text: $username)
                passwordField
            }

            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }

                Spacer()

                Button {
                    folder = createFolder(folder)
                    save(makeProfile(), password)
                    dismiss()
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 430)
        .onAppear(perform: load)
    }

    private var title: String {
        switch mode {
        case .create:
            return "New Server"
        case .edit:
            return "Edit Server"
        }
    }

    private var icon: String {
        switch mode {
        case .create:
            return "plus.circle"
        case .edit:
            return "pencil"
        }
    }

    private var passwordField: some View {
        HStack(spacing: 9) {
            Image(systemName: "key")
                .foregroundStyle(.secondary)
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
            }
            .buttonStyle(.plain)
        }
        .managerField()
    }

    private func field(_ icon: String, _ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
        }
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

    private func makeProfile() -> ServerProfile {
        switch mode {
        case .create:
            return ServerProfile(
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                group: folder
            )
        case .edit(let profile):
            return ServerProfile(
                id: profile.id,
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                group: folder,
                lastConnectedAt: profile.lastConnectedAt
            )
        }
    }
}

private extension View {
    func managerField() -> some View {
        self
            .font(.system(size: 13, weight: .regular))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
