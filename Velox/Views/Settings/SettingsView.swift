import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case profiles = "Profiles"
    case appearance = "Appearance"
    case window = "Window"
    case about = "About Me"
    case updates = "Updates"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .profiles: return "terminal"
        case .appearance: return "circle.lefthalf.filled"
        case .window: return "macwindow"
        case .about: return "info.circle"
        case .updates: return "arrow.down.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: VeloxSettings
    @State private var selection: SettingsSection = .profiles
    @State private var window: NSWindow?

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader

                    switch selection {
                    case .profiles:
                        TerminalProfileSettings()
                    case .appearance:
                        AppearanceSettings()
                    case .window:
                        WindowSettings()
                    case .about:
                        AboutSettings()
                    case .updates:
                        UpdateSettings()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: settings.terminalSurfaceBackgroundColor))
        }
        .frame(width: 720, height: 470)
        .background(Color(nsColor: settings.terminalBackgroundColor))
        .background(WindowAccessor { newWindow in
            window = newWindow
            VeloxWindowStyler.applyTerminalWindowStyle(
                to: newWindow,
                title: "Settings",
                minSize: NSSize(width: 720, height: 470),
                settings: settings
            )
        })
        .onChange(of: settings.appearanceMode) { _, _ in
            applyWindowStyle()
        }
        .onChange(of: settings.isTransparent) { _, _ in
            applyWindowStyle()
        }
        .onChange(of: settings.transparency) { _, _ in
            applyWindowStyle()
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
    }

    private func applyWindowStyle() {
        VeloxWindowStyler.applyTerminalWindowStyle(
            to: window,
            title: "Settings",
            minSize: NSSize(width: 720, height: 470),
            settings: settings
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .frame(width: 18)
                        Text(section.rawValue)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .background(selection == section ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? .primary : .secondary)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 168)
        .background(Color(nsColor: settings.terminalSurfaceBackgroundColor))
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.rawValue)
                .font(.system(size: 22, weight: .semibold))
            Text(headerSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var headerSubtitle: String {
        switch selection {
        case .profiles: return "Terminal text and font defaults."
        case .appearance: return "Window theme and transparency."
        case .window: return "Default dimensions for terminal windows."
        case .about: return "Version, author, and project links."
        case .updates: return "Check, download, and install new releases."
        }
    }
}

private struct TerminalProfileSettings: View {
    @EnvironmentObject private var settings: VeloxSettings

    var body: some View {
        SettingsGroup(title: "Text") {
            Picker("Font", selection: $settings.terminalFontName) {
                ForEach(fonts, id: \.fontName) { font in
                    Text(font.displayName ?? font.fontName)
                        .tag(font.fontName)
                }
            }
            .frame(maxWidth: 360)

            HStack {
                Text("Text Size")
                    .frame(width: 96, alignment: .leading)

                Slider(value: $settings.terminalFontSize, in: 9...32, step: 1)
                    .frame(width: 220)

                Stepper(value: $settings.terminalFontSize, in: 9...32, step: 1) {
                    Text("\(Int(settings.terminalFontSize)) pt")
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 52, alignment: .trailing)
                }
                .labelsHidden()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Preview")
                    .frame(width: 96, alignment: .leading)

                Text("velox ssh user@host")
                    .font(.custom(settings.terminalFontName, size: settings.terminalFontSize))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(Color(nsColor: settings.terminalSurfaceBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color(nsColor: settings.terminalForegroundColor))
            }
        }
    }

    private var fonts: [NSFont] {
        let availableFonts = TerminalFontProvider.availableMonospacedFonts()
        if availableFonts.contains(where: { $0.fontName == settings.terminalFontName }) {
            return availableFonts
        }

        return ([settings.terminalFont] + availableFonts).sorted {
            ($0.displayName ?? $0.fontName) < ($1.displayName ?? $1.fontName)
        }
    }
}

private struct AppearanceSettings: View {
    @EnvironmentObject private var settings: VeloxSettings

    var body: some View {
        SettingsGroup(title: "Theme") {
            Picker("Mode", selection: $settings.appearanceMode) {
                ForEach(VeloxAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Toggle("Transparent Window", isOn: $settings.isTransparent)

            HStack {
                Text("Transparency")
                    .frame(width: 96, alignment: .leading)

                Slider(value: $settings.transparency, in: 0.05...0.55, step: 0.01)
                    .frame(width: 240)
                    .disabled(!settings.isTransparent)

                Text("\(Int(settings.transparency * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }
}

private struct WindowSettings: View {
    @EnvironmentObject private var settings: VeloxSettings

    var body: some View {
        SettingsGroup(title: "Default Size") {
            HStack(spacing: 12) {
                LabeledContent("Width") {
                    TextField("Width", value: $settings.defaultWindowWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                }

                LabeledContent("Height") {
                    TextField("Height", value: $settings.defaultWindowHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 86)
                }
            }

            HStack {
                Text("Quick Sizes")
                    .frame(width: 96, alignment: .leading)

                Button("Compact") {
                    settings.defaultWindowWidth = 820
                    settings.defaultWindowHeight = 500
                }

                Button("Default") {
                    settings.defaultWindowWidth = 940
                    settings.defaultWindowHeight = 580
                }

                Button("Large") {
                    settings.defaultWindowWidth = 1180
                    settings.defaultWindowHeight = 760
                }
            }
        }
    }
}

private struct AboutSettings: View {
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        SettingsGroup(title: "About Velox") {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Velox")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Version \(updateManager.currentVersion) (\(updateManager.currentBuild))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Native macOS terminal, SSH, and SFTP client.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Website") {
                    open("https://motoryang.github.io/velox/")
                }

                Button("GitHub") {
                    open("https://github.com/MotorYang/velox")
                }

                Button("Releases") {
                    open("https://github.com/MotorYang/velox/releases")
                }
            }

            LabeledContent("Author") {
                Text("MotorYang")
            }
        }
    }

    private var appIcon: NSImage {
        if let iconURL = Bundle.main.url(forResource: "logo", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            return icon
        }

        if let icon = NSImage(named: "logo") ?? NSImage(named: "AppIcon") {
            return icon
        }

        return NSApp.applicationIconImage
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct UpdateSettings: View {
    @EnvironmentObject private var settings: VeloxSettings
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        SettingsGroup(title: "Updates") {
            Toggle("Automatically Check for Updates", isOn: $settings.automaticallyChecksForUpdates)

            VStack(alignment: .leading, spacing: 8) {
                Text(updateManager.updateMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Current: \(updateManager.currentVersion) (\(updateManager.currentBuild))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let release = updateManager.latestRelease {
                    Text("Latest: \(release.version) · \(release.assetName)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(updateManager.hasAvailableUpdate ? Color.accentColor : .secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await updateManager.checkForUpdates() }
                } label: {
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isBusy)

                Button {
                    Task { await updateManager.installLatestRelease() }
                } label: {
                    if updateManager.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Install Update", systemImage: "square.and.arrow.down.on.square")
                    }
                }
                .disabled(!updateManager.hasAvailableUpdate || isBusy)

                Button {
                    updateManager.openLatestReleasePage()
                } label: {
                    Label("Open Release Page", systemImage: "safari")
                }
            }

            Text("Install Update downloads the latest zip, quits Velox, replaces the current app bundle, and relaunches Velox. If macOS blocks the replacement because the app is in a protected location, install the release manually.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Because Velox is not Apple-notarized, macOS may still ask you to confirm the first launch after an update.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            if updateManager.latestRelease == nil {
                await updateManager.checkForUpdates()
            }
        }
    }

    private var isBusy: Bool {
        updateManager.isChecking || updateManager.isDownloading || updateManager.isInstalling
    }
}

private struct SettingsGroup<Content: View>: View {
    @EnvironmentObject private var settings: VeloxSettings
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: settings.terminalSurfaceBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
