import Foundation
import Combine

@MainActor
final class ServerDirectoryStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published private(set) var folders: [String] = []
    
    private let defaultsKey = "Velox.ServerProfiles.v1"
    private let foldersKey = "Velox.ServerFolders.v1"
    
    init() {
        load()
    }
    
    func password(for profileID: UUID) -> String {
        authSecret(for: profileID)
    }

    func authSecret(for profileID: UUID) -> String {
        (try? authSecret(for: profileID, reason: "Velox needs your permission to read this server secret.")) ?? ""
    }

    func authSecret(for profileID: UUID, reason: String) throws -> String {
        try KeychainManager.readPassword(account: passwordAccount(for: profileID), reason: reason) ?? ""
    }

    func save(_ profile: ServerProfile, password: String) {
        save(profile, authSecret: password)
    }

    func save(_ profile: ServerProfile, authSecret: String) {
        save(profile, authSecret: Optional(authSecret))
    }

    func save(_ profile: ServerProfile, authSecret: String?) {
        createFolder(named: profile.group)
        var storedProfile = profile
        if let authSecret {
            storedProfile.hasStoredSecret = !authSecret.isEmpty
        }
        
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            if storedProfile.group != profiles[index].group {
                storedProfile.sortOrder = nextSortOrder(in: storedProfile.group)
            } else {
                storedProfile.sortOrder = profiles[index].sortOrder
            }
            profiles[index] = storedProfile
        } else {
            storedProfile.sortOrder = nextSortOrder(in: storedProfile.group)
            profiles.append(storedProfile)
        }
        
        normalizeProfileOrder()
        
        if authSecret == nil {
        } else if authSecret?.isEmpty == true {
            try? KeychainManager.delete(account: passwordAccount(for: profile.id))
        } else if let authSecret {
            try? KeychainManager.savePassword(authSecret, account: passwordAccount(for: profile.id))
        }
        
        persist()
    }

    func authentication(for profile: ServerProfile) throws -> SSHAuthentication {
        switch profile.authenticationMethod {
        case .password:
            return .password(try authSecret(for: profile.id, reason: "Authenticate to connect to \(profile.name)."))
        case .rsaPrivateKey:
            return .rsaPrivateKey(try Data(contentsOf: URL(fileURLWithPath: profile.privateKeyPath)))
        case .ed25519PrivateKey:
            let passphrase = try authSecret(for: profile.id, reason: "Authenticate to unlock the private key for \(profile.name).")
            return .ed25519PrivateKey(
                try Data(contentsOf: URL(fileURLWithPath: profile.privateKeyPath)),
                passphrase: passphrase.isEmpty ? nil : Data(passphrase.utf8)
            )
        }
    }
    
    @discardableResult
    func createFolder(named rawName: String) -> String {
        ensureFolderPath(normalizedFolderName(rawName))
    }

    @discardableResult
    func createFolder(named rawName: String, in parentFolder: String) -> String {
        let parent = normalizedFolderName(parentFolder)
        let leaf = normalizedFolderComponent(rawName)
        return createFolder(named: joinedFolderPath(parent: parent, leaf: leaf))
    }

    func childFolders(of parentFolder: String?) -> [String] {
        folders.filter { parentFolderName(of: $0) == parentFolder }
    }

    func folderDisplayName(_ folder: String) -> String {
        normalizedFolderName(folder).split(separator: "/").last.map(String.init) ?? "Default"
    }

    func parentFolder(of folder: String) -> String? {
        parentFolderName(of: folder)
    }
    
    // MARK: - 文件夹重命名核心逻辑
    @discardableResult
    func renameFolder(from oldName: String, to rawNewName: String) -> String? {
        let normalizedOld = normalizedFolderName(oldName)
        let normalizedNew = joinedFolderPath(
            parent: parentFolderName(of: normalizedOld),
            leaf: normalizedFolderComponent(rawNewName)
        )
        
        // 1. 保护机制：如果名字没变，或者新名字是系统默认分组，或者新名字已经存在，则拒绝重命名
        guard normalizedOld != normalizedNew,
              !folders.contains(normalizedNew) else { return nil }
        
        // 2. 批量更新该文件夹及其子文件夹下所有主机的分组字段
        for index in profiles.indices {
            if profiles[index].group == normalizedOld {
                profiles[index].group = normalizedNew
            } else if profiles[index].group.hasPrefix(normalizedOld + "/") {
                profiles[index].group = normalizedNew + profiles[index].group.dropFirst(normalizedOld.count)
            }
        }
        
        folders = folders.map { folder in
            if folder == normalizedOld {
                return normalizedNew
            }

            if folder.hasPrefix(normalizedOld + "/") {
                return normalizedNew + folder.dropFirst(normalizedOld.count)
            }

            return folder
        }
        normalizeProfileOrder()
        
        // 6. 触发落盘持久化
        persist()
        persistFolders()
        return normalizedNew
    }
    
    func delete(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        try? KeychainManager.delete(account: passwordAccount(for: profile.id))
        normalizeProfileOrder()
        persist()
    }
    
    func deleteFolder(named folder: String) {
        let name = normalizedFolderName(folder)
        profiles
            .filter { $0.group == name || $0.group.hasPrefix(name + "/") }
            .forEach { try? KeychainManager.delete(account: passwordAccount(for: $0.id)) }
        
        profiles.removeAll { $0.group == name || $0.group.hasPrefix(name + "/") }
        folders.removeAll { $0 == name || $0.hasPrefix(name + "/") }
        
        if folders.isEmpty {
            folders = ["Default"]
        }
        
        persist()
        persistFolders()
    }

    func moveProfile(_ profileID: UUID, toFolder rawFolder: String, before targetProfileID: UUID? = nil) {
        guard profileID != targetProfileID else {
            return
        }

        let destinationFolder = createFolder(named: rawFolder)
        guard let sourceIndex = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        var movingProfile = profiles.remove(at: sourceIndex)
        movingProfile.group = destinationFolder

        var destinationProfiles = profiles
            .filter { $0.group == destinationFolder }
            .sorted(by: profileSort)

        if let targetProfileID,
           let targetIndex = destinationProfiles.firstIndex(where: { $0.id == targetProfileID }),
           targetProfileID != profileID {
            destinationProfiles.insert(movingProfile, at: targetIndex)
        } else {
            destinationProfiles.append(movingProfile)
        }

        rewriteProfiles(in: destinationFolder, with: destinationProfiles)
        normalizeProfileOrder()
        persist()
    }

    func moveFolder(_ folder: String, toParent rawParent: String?, before targetFolder: String? = nil) -> String? {
        let source = normalizedFolderName(folder)
        guard source != "Default", folders.contains(source) else {
            return nil
        }

        let parent = rawParent.map(normalizedFolderName)
        if let parent, (parent == source || parent.hasPrefix(source + "/")) {
            return nil
        }

        let destinationBase = uniqueFolderPath(
            parent: parent,
            leaf: folderDisplayName(source),
            excluding: source
        )
        guard destinationBase != source else {
            return source
        }

        let movingFolders = folders.filter { $0 == source || $0.hasPrefix(source + "/") }
        let remainingFolders = folders.filter { !movingFolders.contains($0) }
        let remappedFolders = movingFolders.map { destinationBase + $0.dropFirst(source.count) }

        folders = remainingFolders
        if let targetFolder,
           let targetIndex = folders.firstIndex(of: normalizedFolderName(targetFolder)),
           parentFolderName(of: normalizedFolderName(targetFolder)) == parent {
            folders.insert(contentsOf: remappedFolders, at: targetIndex)
        } else if let siblingIndex = lastChildFolderIndex(of: parent, in: folders) {
            folders.insert(contentsOf: remappedFolders, at: folders.index(after: siblingIndex))
        } else {
            folders.append(contentsOf: remappedFolders)
        }

        for index in profiles.indices {
            if profiles[index].group == source {
                profiles[index].group = destinationBase
            } else if profiles[index].group.hasPrefix(source + "/") {
                profiles[index].group = destinationBase + profiles[index].group.dropFirst(source.count)
            }
        }

        normalizeProfileOrder()
        persist()
        persistFolders()
        return destinationBase
    }
    
    func markConnected(_ profile: ServerProfile) {
        var updated = profile
        updated.lastConnectedAt = Date()
        save(updated, authSecret: nil)
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) else {
            profiles = []
            folders = UserDefaults.standard.stringArray(forKey: foldersKey) ?? ["Default"]
            if folders.isEmpty {
                folders = ["Default"]
            }
            return
        }
        
        profiles = decoded
        folders = UserDefaults.standard.stringArray(forKey: foldersKey) ?? []
        
        for profile in decoded where !folders.contains(profile.group) {
            folders.append(profile.group)
        }
        
        if folders.isEmpty {
            folders = ["Default"]
        }
        
        normalizeProfileOrder()
        persist()
        persistFolders()
    }

    private func normalizeProfileOrder() {
        folders = normalizedFolderList(from: folders + profiles.map(\.group))
        if folders.isEmpty {
            folders = ["Default"]
        }

        var normalized: [ServerProfile] = []

        for folder in folders {
            var folderProfiles = profiles
                .filter { $0.group == folder }
                .sorted(by: profileSort)

            for index in folderProfiles.indices {
                folderProfiles[index].sortOrder = index
            }

            normalized.append(contentsOf: folderProfiles)
        }

        profiles = normalized
    }

    private func rewriteProfiles(in folder: String, with folderProfiles: [ServerProfile]) {
        var updatedProfiles = profiles.filter { $0.group != folder }
        for (index, profile) in folderProfiles.enumerated() {
            var updatedProfile = profile
            updatedProfile.group = folder
            updatedProfile.sortOrder = index
            updatedProfiles.append(updatedProfile)
        }

        profiles = updatedProfiles
    }

    private func nextSortOrder(in folder: String) -> Int {
        (profiles.filter { $0.group == folder }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func profileSort(_ lhs: ServerProfile, _ rhs: ServerProfile) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func ensureFolderPath(_ folder: String) -> String {
        let normalized = normalizedFolderName(folder)
        folders = normalizedFolderList(from: folders + ancestorFolders(for: normalized) + [normalized])
        persistFolders()
        return normalized
    }

    private func normalizedFolderList(from rawFolders: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for rawFolder in rawFolders {
            for folder in ancestorFolders(for: normalizedFolderName(rawFolder)) + [normalizedFolderName(rawFolder)] {
                guard !seen.contains(folder) else { continue }
                seen.insert(folder)
                result.append(folder)
            }
        }

        if !seen.contains("Default") {
            result.insert("Default", at: 0)
        }

        return result
    }

    private func ancestorFolders(for folder: String) -> [String] {
        let components = normalizedFolderName(folder).split(separator: "/").map(String.init)
        guard components.count > 1 else {
            return []
        }

        return (1..<components.count).map { components.prefix($0).joined(separator: "/") }
    }

    private func parentFolderName(of folder: String) -> String? {
        let components = normalizedFolderName(folder).split(separator: "/").map(String.init)
        guard components.count > 1 else {
            return nil
        }

        return components.dropLast().joined(separator: "/")
    }

    private func joinedFolderPath(parent: String?, leaf: String) -> String {
        guard let parent, !parent.isEmpty else {
            return leaf
        }

        return "\(parent)/\(leaf)"
    }

    private func uniqueFolderPath(parent: String?, leaf: String, excluding source: String? = nil) -> String {
        let base = normalizedFolderComponent(leaf)
        var candidate = joinedFolderPath(parent: parent, leaf: base)
        var suffix = 2
        while folders.contains(candidate) && candidate != source {
            candidate = joinedFolderPath(parent: parent, leaf: "\(base) \(suffix)")
            suffix += 1
        }

        return candidate
    }

    private func lastChildFolderIndex(of parent: String?, in folderList: [String]) -> [String].Index? {
        folderList.indices.last { parentFolderName(of: folderList[$0]) == parent }
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }
        
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
    
    private func persistFolders() {
        UserDefaults.standard.set(folders, forKey: foldersKey)
    }
    
    private func normalizedFolderName(_ name: String) -> String {
        let components = name
            .split(separator: "/")
            .map { normalizedFolderComponent(String($0)) }
            .filter { !$0.isEmpty }

        return components.isEmpty ? "Default" : components.joined(separator: "/")
    }

    private func normalizedFolderComponent(_ name: String) -> String {
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return trimmed.isEmpty ? "Default" : trimmed
    }
    
    private func passwordAccount(for profileID: UUID) -> String {
        "server-profile:\(profileID.uuidString):password"
    }
}
