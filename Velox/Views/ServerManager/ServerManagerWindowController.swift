import AppKit
import SwiftUI

@MainActor
final class ServerManagerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var shellWindows: [ShellWindowController] = []

    func open(
        store: ServerDirectoryStore,
        connectInCurrentWindow: @escaping @MainActor (ServerProfile, String) -> Void
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = ServerManagerView(
            serverStore: store,
            connectInCurrentWindow: connectInCurrentWindow,
            connectInNewWindow: { [weak self, store] profile, password in
                let controller = ShellWindowController()
                controller.open(profile: profile, password: password, serverStore: store)
                self?.shellWindows.append(controller)
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Servers"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 680, height: 480)
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
