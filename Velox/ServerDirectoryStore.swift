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
