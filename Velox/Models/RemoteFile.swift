import Foundation
@preconcurrency import Citadel

struct RemoteFile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let longName: String
    let attributes: SFTPFileAttributes

    var isDirectory: Bool {
        guard let permissions = attributes.permissions else {
            return false
        }

        return (permissions & 0o170000) == 0o040000
    }

    init(component: SFTPPathComponent, parentPath: String) {
        self.name = component.filename
        self.path = Self.join(parentPath, component.filename)
        self.longName = component.longname
        self.attributes = component.attributes
        self.id = path
    }

    private static func join(_ directory: String, _ child: String) -> String {
        let normalizedDirectory = directory == "/" ? "" : directory
        return "\(normalizedDirectory)/\(child)"
    }
}
