import AppKit
import SwiftUI

@MainActor
final class VeloxAppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
        openMainWindow()
        checkForUpdatesIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    private func openMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }

        mainWindowController?.open()
    }

    private func applyDockIcon() {
        if let iconURL = Bundle.main.url(forResource: "logo", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
            return
        }

        if let icon = NSImage(named: "logo") ?? NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }
    }

    private func checkForUpdatesIfNeeded() {
        guard VeloxSettings.shared.automaticallyChecksForUpdates else {
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            await UpdateManager.shared.checkForUpdates(silent: true)
        }
    }
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func open() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = ContentView()
            .environmentObject(VeloxSettings.shared)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(VeloxSettings.shared.windowSize)
        window.delegate = self
        VeloxWindowStyler.applyTerminalWindowStyle(
            to: window,
            title: "\(NSUserName())@\(Host.current().localizedName ?? "localhost"):/"
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
