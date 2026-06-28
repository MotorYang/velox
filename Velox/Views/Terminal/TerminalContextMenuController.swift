import AppKit
import ObjectiveC
@preconcurrency import SwiftTerm

@MainActor
enum TerminalContextMenuInstaller {
    private static var controllerKey: UInt8 = 0

    static func install(
        on terminalView: TerminalView,
        serverStore: ServerDirectoryStore? = nil,
        connectProfile: (@MainActor (ServerProfile) -> Void)? = nil
    ) {
        let controller = contextMenuController(for: terminalView)
        controller.configure(serverStore: serverStore, connectProfile: connectProfile)
        terminalView.menu = controller.makeMenu()
    }

    private static func contextMenuController(for terminalView: TerminalView) -> TerminalContextMenuController {
        if let controller = objc_getAssociatedObject(terminalView, &controllerKey) as? TerminalContextMenuController {
            return controller
        }

        let controller = TerminalContextMenuController(terminalView: terminalView)
        objc_setAssociatedObject(terminalView, &controllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }
}

@MainActor
private final class TerminalContextMenuController: NSObject, NSMenuDelegate {
    private weak var terminalView: TerminalView?
    private weak var serverStore: ServerDirectoryStore?
    private var connectProfile: (@MainActor (ServerProfile) -> Void)?

    init(terminalView: TerminalView) {
        self.terminalView = terminalView
    }

    func configure(
        serverStore: ServerDirectoryStore?,
        connectProfile: (@MainActor (ServerProfile) -> Void)?
    ) {
        self.serverStore = serverStore
        self.connectProfile = connectProfile
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("Copy", action: #selector(copy(_:)), key: "c"))
        menu.addItem(menuItem("Paste", action: #selector(paste(_:)), key: "v"))
        menu.addItem(menuItem("Select All", action: #selector(selectAll(_:)), key: "a"))
        if serverStore != nil, connectProfile != nil {
            menu.addItem(.separator())
            menu.addItem(connectServerMenuItem())
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Clear Screen", action: #selector(clearScreen(_:)), key: "k"))
        menu.addItem(menuItem("Interrupt", action: #selector(sendInterrupt(_:))))
        menu.addItem(menuItem("Send EOF", action: #selector(sendEOF(_:))))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(paste(_:)):
                item.isEnabled = NSPasteboard.general.string(forType: .string) != nil
            case #selector(connectServer(_:)):
                item.isEnabled = connectProfile != nil
            default:
                item.isEnabled = true
            }
        }
    }

    @objc private func copy(_ sender: Any?) {
        terminalView?.copy(sender as Any)
    }

    @objc private func paste(_ sender: Any?) {
        terminalView?.paste(sender as Any)
    }

    @objc private func selectAll(_ sender: Any?) {
        terminalView?.selectAll(sender)
    }

    @objc private func clearScreen(_ sender: Any?) {
        sendControlByte(0x0C)
    }

    @objc private func sendInterrupt(_ sender: Any?) {
        sendControlByte(0x03)
    }

    @objc private func sendEOF(_ sender: Any?) {
        sendControlByte(0x04)
    }

    @objc private func connectServer(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? UUID,
              let profile = serverStore?.profiles.first(where: { $0.id == profileID }) else {
            return
        }

        connectProfile?(profile)
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func connectServerMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Connect Server", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "Connect Server")
        item.submenu = makeConnectServerSubmenu()
        return item
    }

    private func makeConnectServerSubmenu() -> NSMenu {
        let menu = NSMenu(title: "Connect Server")
        guard let serverStore else { return menu }

        if serverStore.profiles.isEmpty {
            let emptyItem = NSMenuItem(title: "No Saved Servers", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for profile in serverStore.profiles {
            let title = "\(profile.name)  \(profile.username)@\(profile.host)"
            let item = NSMenuItem(title: title, action: #selector(connectServer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: profile.name)
            menu.addItem(item)
        }

        return menu
    }

    private func sendControlByte(_ byte: UInt8) {
        guard let terminalView else { return }
        let bytes = [byte]
        terminalView.send(source: terminalView.getTerminal(), data: bytes[...])
    }
}
