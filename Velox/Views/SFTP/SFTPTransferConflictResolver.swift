import AppKit
import Foundation

@MainActor
enum SFTPTransferConflictResolver {
    static func uploadableURLs(from urls: [URL], sessionManager: TerminalSessionManager) async -> [URL] {
        var uploadableURLs: [URL] = []

        for url in urls {
            if await sessionManager.remoteItemExists(named: url.lastPathComponent) {
                if confirmOverwrite(name: url.lastPathComponent, location: "remote folder") {
                    uploadableURLs.append(url)
                }
            } else {
                uploadableURLs.append(url)
            }
        }

        return uploadableURLs
    }

    static func shouldDownload(_ remoteFile: RemoteFile, to localURL: URL) -> Bool {
        let destinationURL = remoteFile.isDirectory
            ? localURL.appendingPathComponent(remoteFile.name, isDirectory: true)
            : localURL

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return true
        }

        return confirmOverwrite(name: destinationURL.lastPathComponent, location: "local destination")
    }

    private static func confirmOverwrite(name: String, location: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\"\(name)\" already exists in the \(location)."
        alert.informativeText = "Choose Overwrite to replace it, or Skip to leave the existing item unchanged."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Skip")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
