import AppKit
import SwiftUI

struct RemoteShellSplitView: View {
    @EnvironmentObject private var settings: VeloxSettings
    @ObservedObject var sessionManager: TerminalSessionManager
    @Binding var showsFilePane: Bool
    var serverStore: ServerDirectoryStore? = nil
    var connectProfile: (@MainActor (ServerProfile) -> Void)? = nil
    @State private var filePaneWidth: CGFloat = 300
    @State private var dragStartWidth: CGFloat?
    @State private var selectedFileID: RemoteFile.ID?
    @State private var newFolderName = ""
    @State private var showsNewFolderAlert = false
    @State private var errorMessage: String?

    private let minFilePaneWidth: CGFloat = 220
    private let maxFilePaneWidth: CGFloat = 520
    private let dividerWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                TerminalViewBridge(
                    sessionManager: sessionManager,
                    settings: settings,
                    serverStore: serverStore,
                    connectProfile: connectProfile
                )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: settings.terminalSurfaceBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsFilePane {
                    resizeHandle

                    RemoteFilePane(sessionManager: sessionManager, selectedFileID: $selectedFileID)
                    .frame(width: clampedFilePaneWidth(for: geometry.size.width))
                    .clipped()
                }
            }
            .onAppear {
                filePaneWidth = clampedFilePaneWidth(for: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, width in
                filePaneWidth = clampedFilePaneWidth(for: width)
            }
            .onChange(of: sessionManager.remoteFiles) { _, files in
                if let selectedFileID, !files.contains(where: { $0.id == selectedFileID }) {
                    self.selectedFileID = nil
                }
            }
            .alert("New Folder", isPresented: $showsNewFolderAlert) {
                TextField("Folder name", text: $newFolderName)

                Button("Create") {
                    createFolder()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Create a folder in \(sessionManager.currentRemotePath).")
            }
            .alert("SFTP Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .background(
                SFTPTitlebarAccessoryInstaller(
                    settings: settings,
                    sessionManager: sessionManager,
                    showsFilePane: $showsFilePane,
                    selectedFileID: $selectedFileID,
                    newFolderName: $newFolderName,
                    showsNewFolderAlert: $showsNewFolderAlert,
                    errorMessage: $errorMessage
                )
            )
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: settings.terminalForegroundColor).opacity(settings.appearanceMode == .light ? 0.08 : 0.1))
            .frame(width: dividerWidth)
            .overlay {
                Capsule()
                    .fill(Color(nsColor: settings.terminalForegroundColor).opacity(settings.appearanceMode == .light ? 0.22 : 0.28))
                    .frame(width: 2, height: 42)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = filePaneWidth
                        }

                        filePaneWidth = (dragStartWidth ?? filePaneWidth) - value.translation.width
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private func clampedFilePaneWidth(for totalWidth: CGFloat) -> CGFloat {
        let availableMax = max(minFilePaneWidth, min(maxFilePaneWidth, totalWidth - 360))
        return min(max(filePaneWidth, minFilePaneWidth), availableMax)
    }

    private func createFolder() {
        runSFTPAction {
            try await sessionManager.createRemoteDirectory(named: newFolderName)
        }
    }

    private func runSFTPAction(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

}

private struct SFTPTitlebarControls: View {
    @ObservedObject var settings: VeloxSettings
    @ObservedObject var sessionManager: TerminalSessionManager
    @Binding var showsFilePane: Bool
    @Binding var selectedFileID: RemoteFile.ID?
    @Binding var newFolderName: String
    @Binding var showsNewFolderAlert: Bool
    @Binding var errorMessage: String?
    @State private var showsTransferPopover = false

    var body: some View {
        HStack(spacing: 5) {
            if sessionManager.activeTransfer != nil {
                toolbarButton("arrow.up.arrow.down.circle", "Transfer Progress") {
                    showsTransferPopover.toggle()
                }
                .popover(isPresented: $showsTransferPopover, arrowEdge: .top) {
                    transferPopover
                }
            }

            toolbarButton("arrow.left", "Parent") {
                runSFTPAction {
                    try await sessionManager.goToParentRemoteDirectory()
                }
            }
            .disabled(sessionManager.currentRemotePath == "/" || isBusy || !showsFilePane)

            toolbarButton("arrow.clockwise", "Refresh") {
                runSFTPAction {
                    try await sessionManager.fetchRemoteFiles(at: sessionManager.currentRemotePath)
                }
            }
            .disabled(isBusy || !showsFilePane)

            toolbarButton("square.and.arrow.down", "Download") {
                if let selectedFile {
                    download(selectedFile)
                }
            }
            .disabled(selectedFile == nil || isBusy || !showsFilePane)

            toolbarButton("square.and.arrow.up", "Upload") {
                chooseAndUpload()
            }
            .disabled(isBusy || !showsFilePane)

            toolbarButton("folder.badge.plus", "New Folder") {
                newFolderName = ""
                showsNewFolderAlert = true
            }
            .disabled(isBusy || !showsFilePane)

            toolbarButton(showsFilePane ? "sidebar.right" : "sidebar.left", showsFilePane ? "Hide SFTP" : "Show SFTP") {
                showsFilePane.toggle()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        // .background(Color(nsColor: settings.terminalSurfaceBackgroundColor).opacity(0.88), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        // .overlay {
        //    RoundedRectangle(cornerRadius: 7, style: .continuous)
        //        .stroke(Color(nsColor: settings.terminalForegroundColor).opacity(0.12), lineWidth: 1)
        // }
        .fixedSize()
    }

    private var selectedFile: RemoteFile? {
        guard let selectedFileID else { return nil }
        return sessionManager.remoteFiles.first { $0.id == selectedFileID }
    }

    private var isBusy: Bool {
        sessionManager.isSFTPLoading || sessionManager.activeTransfer != nil
    }

    private var transferPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let transfer = sessionManager.activeTransfer {
                HStack(spacing: 8) {
                    Image(systemName: transfer.kind == .upload ? "square.and.arrow.up" : "square.and.arrow.down")
                        .frame(width: 18)

                    Text(transfer.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }

                ProgressView(value: transfer.fractionCompleted)
                    .progressViewStyle(.linear)

                Text(transfer.byteText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(nsColor: settings.terminalForegroundColor).opacity(0.62))
            } else {
                Text("No active transfer")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: settings.terminalForegroundColor).opacity(0.7))
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(Color(nsColor: settings.terminalSurfaceBackgroundColor))
        .foregroundStyle(Color(nsColor: settings.terminalForegroundColor))
    }

    private func toolbarButton(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 25, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: settings.terminalForegroundColor).opacity(0.88))
        // .background(Color(nsColor: settings.terminalForegroundColor).opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help(help)
    }

    private func chooseAndUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"

        guard panel.runModal() == .OK else {
            return
        }

        runSFTPAction {
            try await sessionManager.uploadItems(localURLs: panel.urls)
        }
    }

    private func download(_ file: RemoteFile) {
        let url: URL?

        if file.isDirectory {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Download"
            url = panel.runModal() == .OK ? panel.url : nil
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            url = panel.runModal() == .OK ? panel.url : nil
        }

        guard let url else {
            return
        }

        runSFTPAction {
            try await sessionManager.downloadFile(file, to: url)
        }
    }

    private func runSFTPAction(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SFTPTitlebarAccessoryInstaller: NSViewRepresentable {
    @ObservedObject var settings: VeloxSettings
    @ObservedObject var sessionManager: TerminalSessionManager
    @Binding var showsFilePane: Bool
    @Binding var selectedFileID: RemoteFile.ID?
    @Binding var newFolderName: String
    @Binding var showsNewFolderAlert: Bool
    @Binding var errorMessage: String?

    private static let identifier = NSUserInterfaceItemIdentifier("VeloxSFTPTitlebarAccessory")

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let rootView = SFTPTitlebarControls(
                settings: settings,
                sessionManager: sessionManager,
                showsFilePane: $showsFilePane,
                selectedFileID: $selectedFileID,
                newFolderName: $newFolderName,
                showsNewFolderAlert: $showsNewFolderAlert,
                errorMessage: $errorMessage
            )

            if let accessory = window.titlebarAccessoryViewControllers.first(where: { $0.view.identifier == Self.identifier }),
               let hostingController = accessory.children.compactMap({ $0 as? NSHostingController<SFTPTitlebarControls> }).first {
                hostingController.rootView = rootView
                hostingController.view.setFrameSize(hostingController.view.fittingSize)
                accessory.view.frame = hostingController.view.frame
                return
            }

            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.identifier = Self.identifier
            hostingController.view.setFrameSize(hostingController.view.fittingSize)

            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = NSView(frame: hostingController.view.frame)
            accessory.view.identifier = Self.identifier
            accessory.layoutAttribute = .right
            accessory.addChild(hostingController)
            accessory.view.addSubview(hostingController.view)
            window.addTitlebarAccessoryViewController(accessory)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            while let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0.view.identifier == Self.identifier }) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
        }
    }
}
