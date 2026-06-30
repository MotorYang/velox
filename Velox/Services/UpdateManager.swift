import AppKit
import Combine
import Foundation

struct VeloxRelease: Sendable {
    let version: String
    let tagName: String
    let name: String
    let url: URL
    let assetName: String
    let downloadURL: URL
}

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isInstalling = false
    @Published private(set) var latestRelease: VeloxRelease?
    @Published private(set) var updateMessage = "No update check has run yet."
    @Published private(set) var downloadedFileURL: URL?

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/MotorYang/velox/releases/latest")!
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var displayVersion: String {
        "Velox \(currentFullVersion)"
    }

    private var currentFullVersion: String {
        "\(currentVersion).\(currentBuild)"
    }

    var hasAvailableUpdate: Bool {
        guard let latestRelease else { return false }
        return Self.compareVersions(latestRelease.version, currentFullVersion) == .orderedDescending
    }

    func checkForUpdates(silent: Bool = false) async {
        if isChecking { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release
            downloadedFileURL = nil

            if Self.compareVersions(release.version, currentFullVersion) == .orderedDescending {
                updateMessage = "Velox \(release.version) is available."
            } else if !silent {
                updateMessage = "Velox is up to date."
            }
        } catch {
            if !silent {
                updateMessage = "Update check failed: \(error.localizedDescription)"
            }
        }
    }

    func downloadLatestRelease() async {
        guard let latestRelease else { return }
        if isDownloading { return }
        isDownloading = true
        defer { isDownloading = false }

        do {
            let (temporaryURL, _) = try await session.download(from: latestRelease.downloadURL)
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            let destinationURL = downloadsURL.appendingPathComponent(latestRelease.assetName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            downloadedFileURL = destinationURL
            updateMessage = "Downloaded \(latestRelease.assetName) to Downloads."
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        } catch {
            updateMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    func installLatestRelease() async {
        guard let latestRelease else { return }
        if isDownloading || isInstalling { return }
        isDownloading = true
        isInstalling = true
        defer {
            isDownloading = false
            isInstalling = false
        }

        do {
            let (temporaryURL, _) = try await session.download(from: latestRelease.downloadURL)
            let installerDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("VeloxUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: installerDirectory, withIntermediateDirectories: true)

            let zipURL = installerDirectory.appendingPathComponent(latestRelease.assetName)
            try FileManager.default.moveItem(at: temporaryURL, to: zipURL)

            let scriptURL = installerDirectory.appendingPathComponent("install-velox-update.sh")
            try installerScript(zipURL: zipURL).write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path, Bundle.main.bundleURL.path, "\(ProcessInfo.processInfo.processIdentifier)"]
            try process.run()

            updateMessage = "Installing \(latestRelease.assetName). Velox will restart."
            NSApp.terminate(nil)
        } catch {
            updateMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    func openLatestReleasePage() {
        guard let url = latestRelease?.url ?? URL(string: "https://github.com/MotorYang/velox/releases") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func fetchLatestRelease() async throws -> VeloxRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = Self.version(from: release.tagName) else {
            throw UpdateError.invalidVersion
        }

        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Velox_arm64_v") && $0.name.hasSuffix(".zip") })
            ?? release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let pageURL = URL(string: release.htmlURL),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateError.missingAsset
        }

        return VeloxRelease(
            version: version,
            tagName: release.tagName,
            name: release.name,
            url: pageURL,
            assetName: asset.name,
            downloadURL: downloadURL
        )
    }

    private func installerScript(zipURL: URL) -> String {
        """
        #!/bin/sh
        APP_PATH="$1"
        APP_PID="$2"
        ZIP_PATH="\(zipURL.path)"
        WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/velox-install.XXXXXX")"

        fail() {
          /usr/bin/osascript -e 'display dialog "Velox update could not be installed automatically. Please download the latest release and replace Velox.app manually." buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1 || true
          exit 1
        }

        while /bin/kill -0 "$APP_PID" 2>/dev/null; do
          /bin/sleep 0.2
        done

        /usr/bin/ditto -x -k "$ZIP_PATH" "$WORK_DIR" || fail
        NEW_APP="$(/usr/bin/find "$WORK_DIR" -maxdepth 3 -name "Velox.app" -type d | /usr/bin/head -n 1)"
        [ -n "$NEW_APP" ] || fail

        BACKUP_PATH="${APP_PATH}.previous"
        /bin/rm -rf "$BACKUP_PATH" || fail

        if [ -d "$APP_PATH" ]; then
          /bin/mv "$APP_PATH" "$BACKUP_PATH" || fail
        fi

        if ! /usr/bin/ditto "$NEW_APP" "$APP_PATH"; then
          /bin/rm -rf "$APP_PATH" >/dev/null 2>&1 || true
          if [ -d "$BACKUP_PATH" ]; then
            /bin/mv "$BACKUP_PATH" "$APP_PATH" >/dev/null 2>&1 || true
          fi
          fail
        fi

        /bin/rm -rf "$BACKUP_PATH" "$WORK_DIR" >/dev/null 2>&1 || true
        /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true
        /usr/bin/open "$APP_PATH"
        """
    }

    private static func version(from tagName: String) -> String? {
        let trimmed = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return trimmed.split(separator: "-").first.map(String.init)
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(leftParts.count, rightParts.count)

        for index in 0..<count {
            let left = index < leftParts.count ? leftParts[index] : 0
            let right = index < rightParts.count ? rightParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }

        return .orderedSame
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case invalidVersion
    case missingAsset

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .invalidVersion:
            return "The latest release does not contain a valid version."
        case .missingAsset:
            return "The latest release does not contain a downloadable Velox zip."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String
    let htmlURL: String
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
