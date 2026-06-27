import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

struct LocalTerminalViewBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> LocalTerminalContainerView {
        LocalTerminalContainerView()
    }

    func updateNSView(_ nsView: LocalTerminalContainerView, context: Context) {
        nsView.scheduleStart()
        nsView.requestFocus()
    }

    static func dismantleNSView(_ nsView: LocalTerminalContainerView, coordinator: ()) {
        nsView.terminate()
    }
}

@MainActor
final class LocalTerminalContainerView: NSView, @preconcurrency LocalProcessTerminalViewDelegate {
    private let terminalView = LocalProcessTerminalView(frame: .zero)
    private var didStartProcess = false
    private var hasQueuedStart = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTerminalView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTerminalView()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleStart()
        requestFocus()
    }

    override func layout() {
        super.layout()
        scheduleStart()
    }

    func scheduleStart() {
        guard !hasQueuedStart else {
            return
        }

        hasQueuedStart = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasQueuedStart = false
            self.startProcessIfPossible()
        }
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self.terminalView)
        }
    }

    func terminate() {
        terminalView.terminate()
    }

    private func setupTerminalView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.04, alpha: 1).cgColor

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.processDelegate = self
        terminalView.metalBufferingMode = .perFrameAggregated
        try? terminalView.setUseMetal(false)
        terminalView.nativeBackgroundColor = NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.04, alpha: 1)
        terminalView.nativeForegroundColor = NSColor(calibratedWhite: 0.86, alpha: 1)
        terminalView.font = TerminalFontProvider.preferredFont()
        terminalView.caretColor = .systemGreen
        terminalView.getTerminal().setCursorStyle(.steadyBlock)

        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func startProcessIfPossible() {
        guard window != nil, bounds.width > 0, bounds.height > 0 else {
            scheduleStart()
            return
        }

        layoutSubtreeIfNeeded()

        guard terminalView.bounds.width > 0, terminalView.bounds.height > 0 else {
            scheduleStart()
            return
        }

        guard !didStartProcess, !terminalView.process.running else {
            requestFocus()
            return
        }

        didStartProcess = true

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shell).lastPathComponent
        terminalView.startProcess(
            executable: shell,
            execName: "-\(shellName)",
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        requestFocus()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        didStartProcess = false
    }
}
