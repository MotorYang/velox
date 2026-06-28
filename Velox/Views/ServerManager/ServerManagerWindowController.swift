import AppKit
import SwiftUI

@MainActor
final class ServerManagerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var shellWindows: [ShellWindowController] = []

    func open(
        store: ServerDirectoryStore,
        connectInCurrentWindow: @escaping @MainActor (ServerProfile, SSHAuthentication) -> Void
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = ServerManagerView(
            serverStore: store,
            connectInCurrentWindow: connectInCurrentWindow,
            connectInNewWindow: { [weak self, store] profile, auth in
                let controller = ShellWindowController()
                controller.open(profile: profile, auth: auth, serverStore: store)
                self?.shellWindows.append(controller)
            }
        )
        .environmentObject(VeloxSettings.shared)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.delegate = self
        VeloxWindowStyler.applyTerminalWindowStyle(
            to: window,
            title: "Servers",
            minSize: NSSize(width: 680, height: 480)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
