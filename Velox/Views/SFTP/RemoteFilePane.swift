import AppKit
import SwiftUI

struct RemoteFilePane: View {
    @EnvironmentObject private var settings: VeloxSettings
    @ObservedObject var sessionManager: TerminalSessionManager
    @Binding var selectedFileID: RemoteFile.ID?

    @State private var renameName = ""
    @State private var fileToRename: RemoteFile?
    @State private var fileToDelete: RemoteFile?
    @State private var showsRenameAlert = false
    @State private var errorMessage: String?
    @State private var isDropTargeted = false
    @State private var remotePathText = "/"

    private let rowHeight: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar

            Divider()
                .overlay(dividerColor)

            fileList
        }
        .foregroundStyle(primaryForeground)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: settings.terminalSurfaceBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(dividerColor)
                .frame(width: 1)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            upload(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .alert("Rename", isPresented: $showsRenameAlert) {
            TextField("Name", text: $renameName)

            Button("Rename") {
                renameSelectedFile()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(fileToRename?.name ?? "")
        }
        .confirmationDialog(
            "Delete \(fileToDelete?.name ?? "item")?",
            isPresented: Binding(
                get: { fileToDelete != nil },
                set: { if !$0 { fileToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deletePendingFile()
            }

            Button("Cancel", role: .cancel) {
                fileToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("SFTP Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            remotePathText = sessionManager.currentRemotePath
        }
        .onChange(of: sessionManager.currentRemotePath) { _, newPath in
            remotePathText = newPath
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            if sessionManager.isSFTPLoading || sessionManager.activeTransfer != nil {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            }

            TextField("Remote path", text: $remotePathText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(secondaryForeground)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .onSubmit {
                    jumpToPath()
                }
                .help(sessionManager.currentRemotePath)

            Spacer(minLength: 4)

            Text("\(sessionManager.remoteFiles.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(secondaryForeground)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var fileList: some View {
        ZStack {
            if sessionManager.remoteFiles.isEmpty && !sessionManager.isSFTPLoading {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: []) {
                        ForEach(sessionManager.remoteFiles) { file in
                            fileRow(file)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .background(SFTPScrollerStyler())
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(secondaryForeground)

            Text("Empty Folder")
                .font(.system(size: 13, weight: .medium))

            Text("Drop files here or use the upload button.")
                .font(.system(size: 11))
                .foregroundStyle(secondaryForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(file.isDirectory ? folderColor : secondaryForeground)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12, weight: selectedFileID == file.id ? .semibold : .regular))
                    .lineLimit(1)

                if let modifiedAt = file.displayModifiedAt {
                    Text(modifiedAt)
                        .font(.system(size: 9))
                        .foregroundStyle(secondaryForeground.opacity(0.78))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(file.isDirectory ? "--" : file.displaySize)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(secondaryForeground)
                .lineLimit(1)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 7)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .background(rowBackground(for: file), in: RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) {
            open(file)
        }
        .onTapGesture {
            selectedFileID = file.id
        }
        .contextMenu {
            Button {
                open(file)
            } label: {
                Label(file.isDirectory ? "Open" : "Download", systemImage: file.isDirectory ? "folder" : "square.and.arrow.down")
            }

            if !file.isDirectory {
                Button {
                    download(file)
                } label: {
                    Label("Download", systemImage: "square.and.arrow.down")
                }
            } else {
                Button {
                    download(file)
                } label: {
                    Label("Download Folder", systemImage: "square.and.arrow.down")
                }
            }

            Button {
                startRename(file)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                fileToDelete = file
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var selectedFile: RemoteFile? {
        guard let selectedFileID else { return nil }
        return sessionManager.remoteFiles.first { $0.id == selectedFileID }
    }

    private func rowBackground(for file: RemoteFile) -> Color {
        if selectedFileID == file.id {
            return Color.accentColor.opacity(settings.appearanceMode == .light ? 0.2 : 0.24)
        }

        return .clear
    }

    private func open(_ file: RemoteFile) {
        selectedFileID = file.id
        if file.isDirectory {
            runSFTPAction {
                try await sessionManager.fetchRemoteFiles(at: file.path)
            }
        } else {
            download(file)
        }
    }

    private func upload(_ urls: [URL]) {
        runSFTPAction {
            try await sessionManager.uploadItems(localURLs: urls)
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

    private func jumpToPath() {
        runSFTPAction {
            try await sessionManager.changeRemoteDirectory(to: remotePathText)
        }
    }

    private func startRename(_ file: RemoteFile) {
        fileToRename = file
        renameName = file.name
        showsRenameAlert = true
    }

    private func renameSelectedFile() {
        guard let fileToRename else {
            return
        }

        runSFTPAction {
            try await sessionManager.renameRemoteFile(fileToRename, to: renameName)
            self.fileToRename = nil
        }
    }

    private func deletePendingFile() {
        guard let file = fileToDelete else {
            return
        }

        runSFTPAction {
            try await sessionManager.deleteRemoteFile(file)
            if selectedFileID == file.id {
                selectedFileID = nil
            }
            fileToDelete = nil
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

    private var primaryForeground: Color {
        Color(nsColor: settings.terminalForegroundColor)
    }

    private var secondaryForeground: Color {
        primaryForeground.opacity(settings.appearanceMode == .light ? 0.58 : 0.62)
    }

    private var dividerColor: Color {
        primaryForeground.opacity(settings.appearanceMode == .light ? 0.12 : 0.1)
    }

    private var folderColor: Color {
        settings.appearanceMode == .light
            ? Color(red: 0.78, green: 0.52, blue: 0.08)
            : Color(red: 0.95, green: 0.72, blue: 0.18)
    }
}

private struct SFTPScrollerStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        applyScrollerStyle(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyScrollerStyle(from: nsView)
    }

    private func applyScrollerStyle(from view: NSView) {
        for delay in [0.0, 0.05, 0.18] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let scrollView = view.nearestAncestor(of: NSScrollView.self) else {
                    return
                }

                scrollView.scrollerStyle = .overlay
                scrollView.hasVerticalScroller = true
                scrollView.verticalScroller?.scrollerStyle = .overlay
                scrollView.verticalScroller?.controlSize = .small
                TerminalChromeStyler.apply(to: scrollView)
            }
        }
    }
}

private extension NSView {
    func nearestAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let typedView = view as? T {
                return typedView
            }

            current = view.superview
        }

        return nil
    }
}
