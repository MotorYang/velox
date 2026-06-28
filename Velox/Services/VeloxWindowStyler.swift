import AppKit

@MainActor
enum VeloxWindowStyler {
    private static let legacyMainTitlebarAccessoryIdentifier = NSUserInterfaceItemIdentifier("VeloxTitlebarAccessory")

    static func applyTerminalWindowStyle(
        to window: NSWindow?,
        title: String? = nil,
        minSize: NSSize = NSSize(width: 720, height: 420),
        settings: VeloxSettings = .shared
    ) {
        guard let window else { return }

        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.toolbar = nil
        window.minSize = minSize

        if let title {
            window.title = title
        }

        removeLegacyMainTitlebarAccessory(from: window)
        showStandardWindowButtons(for: window)
        settings.apply(to: window)
        window.titlebarAppearsTransparent = true
        makeContentViewTransparent(window.contentView)
    }

    private static func makeContentViewTransparent(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor

        for subview in view.subviews {
            makeContentViewTransparent(subview)
        }
    }

    private static func removeLegacyMainTitlebarAccessory(from window: NSWindow) {
        while let index = window.titlebarAccessoryViewControllers.firstIndex(where: {
            $0.view.identifier == legacyMainTitlebarAccessoryIdentifier
        }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }

    private static func showStandardWindowButtons(for window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}
