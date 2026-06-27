import AppKit
import SwiftUI

struct RemoteShellSplitView: View {
    @ObservedObject var sessionManager: TerminalSessionManager
    @Binding var showsFilePane: Bool
    @State private var filePaneWidth: CGFloat = 300
    @State private var dragStartWidth: CGFloat?

    private let minFilePaneWidth: CGFloat = 220
    private let maxFilePaneWidth: CGFloat = 520
    private let dividerWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    TerminalViewBridge(sessionManager: sessionManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsFilePane {
                        resizeHandle(totalWidth: geometry.size.width)

                        RemoteFilePane(sessionManager: sessionManager) {
                            showsFilePane = false
                        }
                        .frame(width: filePaneWidth)
                        .clipped()
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }

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

    private func resizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color(red: 0.07, green: 0.074, blue: 0.076))
            .frame(width: dividerWidth)
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(width: 2, height: 42)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = filePaneWidth
                        }

                        let proposedWidth = (dragStartWidth ?? filePaneWidth) - value.translation.width
                        filePaneWidth = clamped(proposedWidth, totalWidth: totalWidth)
                    }
                    .onEnded { _ in
                        filePaneWidth = clamped(filePaneWidth, totalWidth: totalWidth)
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
        .foregroundStyle(.white.opacity(0.88))
        .background(.ultraThinMaterial, in: Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .help("打开远程文件夹")
    }

    private func clampedFilePaneWidth(for totalWidth: CGFloat) -> CGFloat {
        clamped(filePaneWidth, totalWidth: totalWidth)
    }

    private func clamped(_ width: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let availableMax = max(minFilePaneWidth, min(maxFilePaneWidth, totalWidth - 360))
        return min(max(width, minFilePaneWidth), availableMax)
    }
}
