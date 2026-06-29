<p align="center">
  <img src="Velox/Supporting%20Files/app_logo.png" alt="Velox Logo" width="120">
</p>

<h1 align="center">Velox</h1>

<p align="center">
  Native macOS terminal, SSH, and SFTP client built with Swift.
</p>

<p align="center">
  English | <a href="README_CN.md">简体中文</a>
</p>

## Overview

Velox is a native macOS terminal and SSH/SFTP client. It uses SwiftUI and AppKit for the desktop experience, SwiftTerm for terminal rendering, and Citadel, SwiftNIO, and Swift Crypto for pure Swift SSH and SFTP support.

The project focuses on keeping local terminals, remote shells, server profiles, credential storage, and file transfer in one lightweight window, reducing the need to switch between Terminal, Finder, and a separate SFTP app.

## Features

- Local terminal window with working-directory title updates.
- Remote SSH shell connections with password, RSA private key, and Ed25519 private key authentication.
- SFTP file pane for remote directory browsing, path jumping, uploads, downloads, renaming, and deletion.
- Drag files or folders from Finder into the remote SFTP pane to upload.
- Server profile manager with folders, cloning, editing, deletion, and double-click connection.
- Passwords and private-key passphrases stored in macOS Keychain.
- Reconnect scheduling after SSH disconnects.
- Configurable terminal font, font size, window size, light/dark appearance, and transparency.
- macOS menu shortcuts:
  - `Command-P`: open the server manager.
  - `Command-F`: open the remote file pane.

## Tech Stack

- Swift / SwiftUI / AppKit
- SwiftTerm 1.13.0
- Citadel 0.12.1
- SwiftNIO 2.101.2
- Swift Crypto 3.15.1
- macOS Keychain Services
- Xcode project + Swift Package Manager

Dependency versions are pinned in `Velox.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Requirements

- macOS 26.5 or later
- Xcode 26 or compatible version
- Network access for Swift Package Manager dependency resolution on first build

> The current Xcode project sets `MACOSX_DEPLOYMENT_TARGET` to `26.5`. If you need to support an older macOS version, verify SwiftUI, AppKit, and third-party dependency compatibility before changing the deployment target.

## Build and Run

1. Clone the repository:

   ```bash
   git clone https://github.com/MotorYang/velox.git
   cd Velox
   ```

2. Open the Xcode project:

   ```bash
   open Velox.xcodeproj
   ```

3. Select the `Velox` scheme in Xcode.

4. Wait for Swift Package Manager to resolve dependencies, then click Run.

You can also build from the command line:

```bash
xcodebuild -project Velox.xcodeproj -scheme Velox -configuration Debug build
```

## Usage

### Local Terminal

Velox starts in a local terminal. The window title follows the current local user, host name, and working directory.

### Add a Server

1. Press `Command-P` to open the server manager.
2. Click `New Server`.
3. Enter the name, host, port, username, and authentication method.
4. Save the profile and double-click it to connect.

Supported authentication methods:

- Password: the password is stored in macOS Keychain.
- RSA Key: select a local RSA private key file.
- Ed25519 Key: select a local Ed25519 private key file and optionally provide a passphrase.

### File Transfer

After connecting over SSH, Velox opens the remote file pane:

- Double-click a directory to enter it.
- Double-click a file to download it.
- Drag local files or folders into the pane to upload them.
- Use row actions to rename or delete remote files.
- Type a remote path in the path bar and press Return to jump.

## Automated Releases

Pushing code to the `production` branch triggers the `Build and Release` GitHub Actions workflow. The workflow builds the macOS app in Release configuration for Apple Silicon, packages `Velox.app` as `Velox_arm64_v<version>.zip`, and publishes it to [GitHub Releases](https://github.com/MotorYang/velox/releases).

Without an Apple Developer Program account, the generated artifact is ad-hoc signed but not notarized. macOS Gatekeeper will still show an "Apple cannot verify this app" warning on first launch.

For ad-hoc builds, open the app with one of these methods:

1. Right-click `Velox.app`, choose Open, then confirm Open.
2. Or open System Settings > Privacy & Security, then choose Open Anyway after the first blocked launch.
3. For local testing only, remove the quarantine flag with `xattr -dr com.apple.quarantine /Applications/Velox.app`.

If the release runner is self-hosted and needs the local proxy at `127.0.0.1:10808`, set the repository variable `USE_LOCAL_PROXY` to `true`. Do not enable it on GitHub-hosted runners unless that proxy exists inside the runner environment.

To publish a Gatekeeper-friendly macOS release, enroll in the Apple Developer Program and configure these GitHub repository secrets:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12` certificate.
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12` certificate.
- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for the Apple ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

When all notarization secrets are present, the release workflow Developer ID signs `Velox.app`, submits it to Apple notarization, staples the ticket, verifies it with `spctl`, and publishes a `notarized` zip asset. Without those secrets, the workflow falls back to an `adhoc` zip asset.

## Project Structure

```text
Velox/
  App/                  App entry point, menu commands, and AppDelegate
  Core/                 Keychain, SSH authentication, font, and input helpers
  Models/               Server profile, remote file, and settings models
  Services/             SSH/SFTP sessions, window styling, and server profile storage
  Views/
    Main/               Main window container
    Terminal/           SwiftTerm / AppKit bridge and terminal window
    SFTP/               Remote file pane, transfer conflict handling, and local terminal bridge
    ServerManager/      Server manager
    Settings/           Settings UI
  Supporting Files/     Assets, icons, and entitlements
```

## Security and Privacy

- Server profiles are stored in `UserDefaults`; passwords and private-key passphrases are stored in macOS Keychain.
- Private key files are not copied into the app data directory. Velox stores only the private-key path in the server profile.
- The current SSH host-key validation strategy accepts any host key in code, which is convenient during development. Before production use, add known_hosts validation or a fingerprint confirmation flow.

## Contributing

Issues and pull requests are welcome. Before changing the project, please check that:

- New features fit native macOS interaction patterns.
- SSH/SFTP work stays asynchronous and does not block the main thread.
- UI state updates return to `MainActor`.
- Credential-related changes continue using Keychain and do not write secrets to plain-text storage.

## License

Velox is released under the MIT License. See [LICENSE](LICENSE) for details.
