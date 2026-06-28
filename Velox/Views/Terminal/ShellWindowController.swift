import AppKit
import SwiftUI

@MainActor
final class ShellWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func open(profile: ServerProfile, password: String, serverStore: ServerDirectoryStore) {
        let shellView = ShellWindowView(profile: profile, password: password, serverStore: serverStore)
            .environmentObject(VeloxSettings.shared)
        let hostingController = NSHostingController(rootView: shellView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = profile.name
        window.setContentSize(VeloxSettings.shared.windowSize)
        window.minSize = NSSize(width: 720, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.delegate = self
        VeloxSettings.shared.apply(to: window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct ShellWindowView: View {
    @EnvironmentObject private var settings: VeloxSettings
    let profile: ServerProfile
    let password: String
    @ObservedObject var serverStore: ServerDirectoryStore

    @StateObject private var sessionManager = TerminalSessionManager()
    @State private var didStartConnection = false
    @State private var connectionError: String?
    @State private var showsSFTPPane = false
    @State private var window: NSWindow?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: settings.backgroundGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                .ignoresSafeArea()

            if sessionManager.isConnected {
                RemoteShellSplitView(sessionManager: sessionManager, showsFilePane: $showsSFTPPane)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(connectionError ?? sessionManager.statusMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(WindowAccessor { newWindow in
            window = newWindow
            settings.apply(to: newWindow)
        })
        .focusedSceneValue(\.openRemoteFolderAction, sessionManager.isConnected ? {
            showsSFTPPane = true
        } : nil)
        .onAppear {
            sessionManager.onShellExit = {
                window?.close()
            }
        }
        .onChange(of: sessionManager.isConnected) { _, isConnected in
            showsSFTPPane = isConnected
        }
        .onChange(of: settings.appearanceMode) { _, _ in
            settings.apply(to: window)
        }
        .onChange(of: settings.isTransparent) { _, _ in
            settings.apply(to: window)
        }
        .onChange(of: settings.transparency) { _, _ in
            settings.apply(to: window)
        }
        .onChange(of: settings.defaultWindowWidth) { _, _ in
            settings.apply(to: window, resize: true)
        }
        .onChange(of: settings.defaultWindowHeight) { _, _ in
            settings.apply(to: window, resize: true)
        }
        .preferredColorScheme(settings.appearanceMode.colorScheme)
        .task {
            guard !didStartConnection else { return }
            didStartConnection = true

            do {
                try await sessionManager.connect(
                    host: profile.host,
                    port: profile.port,
                    user: profile.username,
                    auth: .password(password)
                )
                serverStore.markConnected(profile)
            } catch {
                connectionError = "SSH connection failure: \(error.localizedDescription)"
            }
        }
    }
}
