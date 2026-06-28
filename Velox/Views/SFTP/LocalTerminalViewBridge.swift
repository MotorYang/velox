import AppKit
import SwiftUI
@preconcurrency import SwiftTerm

struct LocalTerminalViewBridge: NSViewRepresentable {
    @ObservedObject var settings: VeloxSettings
    @ObservedObject var serverStore: ServerDirectoryStore
    @Binding var currentDirectory: String
    let connectProfile: @MainActor (ServerProfile) -> Void

    func makeNSView(context: Context) -> LocalTerminalContainerView {
        let view = LocalTerminalContainerView(settings: settings)
        view.onCurrentDirectoryChange = { directory in
            currentDirectory = directory
        }
        view.serverStore = serverStore
        view.connectProfile = connectProfile
        return view
    }

    func updateNSView(_ nsView: LocalTerminalContainerView, context: Context) {
        nsView.onCurrentDirectoryChange = { directory in
            currentDirectory = directory
        }
        nsView.serverStore = serverStore
        nsView.connectProfile = connectProfile
        nsView.apply(settings: settings)
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
    private var settings: VeloxSettings
    private var didStartProcess = false
    private var hasQueuedStart = false
    var onCurrentDirectoryChange: ((String) -> Void)?
    weak var serverStore: ServerDirectoryStore?
    var connectProfile: (@MainActor (ServerProfile) -> Void)?

    init(settings: VeloxSettings) {
        self.settings = settings
        super.init(frame: .zero)
        setupTerminalView()
        apply(settings: settings)
    }

    override init(frame frameRect: NSRect) {
        self.settings = .shared
        super.init(frame: frameRect)
        setupTerminalView()
        apply(settings: settings)
    }

    required init?(coder: NSCoder) {
        self.settings = .shared
        super.init(coder: coder)
        setupTerminalView()
        apply(settings: settings)
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
            KeyboardInputSourceSwitcher.switchToEnglish()
        }
    }

    func terminate() {
        terminalView.terminate()
    }

    func apply(settings: VeloxSettings) {
        self.settings = settings
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = settings.terminalSurfaceBackgroundColor.cgColor
        terminalView.wantsLayer = true
        terminalView.layer?.isOpaque = false
        terminalView.nativeBackgroundColor = settings.terminalSurfaceBackgroundColor
        terminalView.nativeForegroundColor = settings.terminalForegroundColor
        terminalView.font = settings.terminalFont
        TerminalChromeStyler.apply(to: terminalView)
        TerminalContextMenuInstaller.install(
            on: terminalView,
            serverStore: serverStore,
            connectProfile: connectProfile
        )
        terminalView.needsDisplay = true
    }

    private func setupTerminalView() {
        wantsLayer = true

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.wantsLayer = true
        terminalView.layer?.isOpaque = false
        terminalView.processDelegate = self
        terminalView.metalBufferingMode = .perFrameAggregated
        try? terminalView.setUseMetal(false)
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
            currentDirectory: settingsInitialDirectory
        )
        onCurrentDirectoryChange?(settingsInitialDirectory)
        requestFocus()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory = normalizedDirectory(directory) else { return }
        onCurrentDirectoryChange?(directory)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        didStartProcess = false
    }

    private var settingsInitialDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func normalizedDirectory(_ directory: String?) -> String? {
        guard let directory, !directory.isEmpty else {
            return nil
        }

        if let url = URL(string: directory), url.isFileURL {
            return url.path
        }

        return directory
    }
}
