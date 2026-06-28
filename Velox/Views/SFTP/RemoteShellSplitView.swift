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

    private let minFilePaneWidth: CGFloat = 220
    private let maxFilePaneWidth: CGFloat = 520
    private let dividerWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
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

                        RemoteFilePane(sessionManager: sessionManager) {
                            showsFilePane = false
                        }
                        .frame(width: clampedFilePaneWidth(for: geometry.size.width))
                        .clipped()
                    }
                }
                //.transaction { transaction in
                //    transaction.animation = nil
                //}

                if !showsFilePane {
                    collapsedFileButton
                        .padding(.trailing, 14)
                }
            }
            .onAppear {
                filePaneWidth = clampedFilePaneWidth(for: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, width in
                filePaneWidth = clampedFilePaneWidth(for: width)
            }
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

    private var collapsedFileButton: some View {
        Button {
            showsFilePane = true
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: settings.terminalForegroundColor).opacity(0.88))
        .background(Color(nsColor: settings.terminalSurfaceBackgroundColor), in: Circle())
        .overlay {
            Circle()
                .stroke(Color(nsColor: settings.terminalForegroundColor).opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(settings.appearanceMode == .light ? 0.12 : 0.28), radius: 14, y: 8)
        .help("Open remote folder")
    }

    private func clampedFilePaneWidth(for totalWidth: CGFloat) -> CGFloat {
        let availableMax = max(minFilePaneWidth, min(maxFilePaneWidth, totalWidth - 360))
        return min(max(filePaneWidth, minFilePaneWidth), availableMax)
    }
}
