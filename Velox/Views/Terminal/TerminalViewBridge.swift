import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

struct TerminalViewBridge: NSViewRepresentable {
    @ObservedObject var sessionManager: TerminalSessionManager

    final class Coordinator: NSObject, TerminalViewDelegate {
        let sessionManager: TerminalSessionManager

        @MainActor
        init(_ parent: TerminalViewBridge) {
            self.sessionManager = parent.sessionManager
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor [sessionManager] in
                sessionManager.resizeRemoteTerminal(cols: newCols, rows: newRows)
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            Task { @MainActor [sessionManager] in
                sessionManager.syncRemoteFolder(to: directory)
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            Task { @MainActor [sessionManager] in
                sessionManager.sendInputToRemote(bytes: bytes[...])
            }
        }

        func scrolled(source: TerminalView, position: Double) {}

        func clipboardCopy(source: TerminalView, content: Data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(content, forType: .string)
        }

        func clipboardRead(source: TerminalView) -> Data? {
            NSPasteboard.general.data(forType: .string)
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.terminalDelegate = context.coordinator
        view.metalBufferingMode = .perFrameAggregated
        try? view.setUseMetal(false)
        view.nativeBackgroundColor = .clear
        view.font = TerminalFontProvider.preferredFont()
        view.feed(text: "\(sessionManager.statusMessage)\r\n")

        startBridge(afterViewUpdate: view)

        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        startBridge(afterViewUpdate: nsView)
        nsView.needsDisplay = true
    }

    private func startBridge(afterViewUpdate view: TerminalView) {
        DispatchQueue.main.async { [sessionManager] in
            let terminal = view.getTerminal()
            sessionManager.startTerminalBridge(initialCols: terminal.cols, initialRows: terminal.rows) { bytes in
                view.feed(byteArray: bytes)
            }
            view.window?.makeFirstResponder(view)
        }
    }
}
