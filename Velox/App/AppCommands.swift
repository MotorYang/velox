import SwiftUI

struct OpenServerManagerActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct OpenRemoteFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openServerManagerAction: (() -> Void)? {
        get { self[OpenServerManagerActionKey.self] }
        set { self[OpenServerManagerActionKey.self] = newValue }
    }

    var openRemoteFolderAction: (() -> Void)? {
        get { self[OpenRemoteFolderActionKey.self] }
        set { self[OpenRemoteFolderActionKey.self] = newValue }
    }
}

struct VeloxCommands: Commands {
    @FocusedValue(\.openServerManagerAction) private var openServerManager
    @FocusedValue(\.openRemoteFolderAction) private var openRemoteFolder

    var body: some Commands {
        CommandMenu("Server") {
            Button("Manager") {
                openServerManager?()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(openServerManager == nil)

            Divider()

            Button("Open Remote Folder") {
                openRemoteFolder?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(openRemoteFolder == nil)
        }
    }
}
