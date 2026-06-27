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
        CommandMenu("连接") {
            Button("服务器管理") {
                openServerManager?()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(openServerManager == nil)

            Divider()

            Button("打开远程文件夹") {
                openRemoteFolder?()
            }
            .disabled(openRemoteFolder == nil)
        }
    }
}
