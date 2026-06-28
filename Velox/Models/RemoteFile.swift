import Foundation
@preconcurrency import Citadel

struct RemoteFile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let longName: String
    let attributes: SFTPFileAttributes
    let displaySize: String
    let displayModifiedAt: String?

    var isDirectory: Bool {
        guard let permissions = attributes.permissions else {
            return false
        }

        return (permissions & 0o170000) == 0o040000
    }

    var size: UInt64? {
        attributes.size
    }

    var modifiedAt: Date? {
        attributes.accessModificationTime?.modificationTime
    }

    var permissionsText: String {
        guard let permissions = attributes.permissions else {
            return "---"
        }

        return String(format: "%04o", permissions & 0o7777)
    }

    var kindLabel: String {
        isDirectory ? "Folder" : "File"
    }

    init(component: SFTPPathComponent, parentPath: String) {
        self.name = component.filename
        self.path = Self.join(parentPath, component.filename)
        self.longName = component.longname
        self.attributes = component.attributes
        self.displaySize = Self.formatSize(component.attributes.size)
        self.displayModifiedAt = Self.formatModifiedAt(component.attributes.accessModificationTime?.modificationTime)
        self.id = path
    }

    private static func join(_ directory: String, _ child: String) -> String {
        let normalizedDirectory = directory == "/" ? "" : directory
        return "\(normalizedDirectory)/\(child)"
    }

    private static func formatSize(_ size: UInt64?) -> String {
        guard let size else {
            return "--"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private static func formatModifiedAt(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
