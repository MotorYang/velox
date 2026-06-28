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
        (try? KeychainManager.readPassword(account: passwordAccount(for: profileID))) ?? ""
    }
    
    func save(_ profile: ServerProfile, password: String) {
        createFolder(named: profile.group)
        
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        
        profiles.sort {
            if $0.group != $1.group {
                return $0.group.localizedStandardCompare($1.group) == .orderedAscending
            }
            
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        
        if !password.isEmpty {
            try? KeychainManager.savePassword(password, account: passwordAccount(for: profile.id))
        }
        
        persist()
    }
    
    @discardableResult
    func createFolder(named rawName: String) -> String {
        let name = normalizedFolderName(rawName)
        if !folders.contains(name) {
            folders.append(name)
            folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            persistFolders()
        }
        
        return name
    }
    
    // MARK: - 文件夹重命名核心逻辑
    func renameFolder(from oldName: String, to rawNewName: String) {
        let normalizedOld = normalizedFolderName(oldName)
        let normalizedNew = normalizedFolderName(rawNewName)
        
        // 1. 保护机制：如果名字没变，或者新名字是系统默认分组，或者新名字已经存在，则拒绝重命名
        guard normalizedOld != normalizedNew,
              !folders.contains(normalizedNew) else { return }
        
        // 2. 批量更新该文件夹下所有主机的分组字段 (修改内存状态)
        for index in profiles.indices {
            if profiles[index].group == normalizedOld {
                profiles[index].group = normalizedNew
            }
        }
        
        // 3. 重新对 profiles 排序（防止因 group 改变导致原有树状排序错乱）
        profiles.sort {
            if $0.group != $1.group {
                return $0.group.localizedStandardCompare($1.group) == .orderedAscending
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        
        // 4. 更新文件夹列表本身
        if let folderIndex = folders.firstIndex(of: normalizedOld) {
            folders[folderIndex] = normalizedNew
        } else if !folders.contains(normalizedNew) {
            folders.append(normalizedNew)
        }
        
        // 5. 确保文件夹保持标准字典序排序
        folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        
        // 6. 触发落盘持久化
        persist()
        persistFolders()
    }
    
    func delete(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        try? KeychainManager.delete(account: passwordAccount(for: profile.id))
        persist()
    }
    
    func deleteFolder(named folder: String) {
        let name = normalizedFolderName(folder)
        profiles
            .filter { $0.group == name }
            .forEach { try? KeychainManager.delete(account: passwordAccount(for: $0.id)) }
        
        profiles.removeAll { $0.group == name }
        folders.removeAll { $0 == name }
        
        if folders.isEmpty {
            folders = ["Default"]
        }
        
        persist()
        persistFolders()
    }
    
    func markConnected(_ profile: ServerProfile) {
        var updated = profile
        updated.lastConnectedAt = Date()
        save(updated, password: password(for: profile.id))
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
        
        folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        persistFolders()
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Default" : trimmed
    }
    
    private func passwordAccount(for profileID: UUID) -> String {
        "server-profile:\(profileID.uuidString):password"
    }
}
