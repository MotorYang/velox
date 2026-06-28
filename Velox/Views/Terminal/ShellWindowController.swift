import AppKit
import SwiftUI

@MainActor
final class ShellWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func open(profile: ServerProfile, password: String, serverStore: ServerDirectoryStore) {
        let shellView = ShellWindowView(profile: profile, password: password, serverStore: serverStore)
        let hostingController = NSHostingController(rootView: shellView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = profile.name
        window.setContentSize(NSSize(width: 940, height: 580))
        window.minSize = NSSize(width: 720, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct ShellWindowView: View {
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
            Color(red: 0.035, green: 0.038, blue: 0.04)
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
        .background(WindowAccessor { window = $0 })
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
