import SwiftUI

struct RemoteFilePane: View {
    @EnvironmentObject private var settings: VeloxSettings
    @ObservedObject var sessionManager: TerminalSessionManager
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("SFTP", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    Task { try? await sessionManager.fetchRemoteFiles(at: sessionManager.currentRemotePath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    close()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Text(sessionManager.currentRemotePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(secondaryForeground)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
                .overlay(dividerColor)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sessionManager.remoteFiles) { file in
                        HStack(spacing: 9) {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(file.isDirectory ? folderColor : secondaryForeground)
                                .frame(width: 16)

                            Text(file.name)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .foregroundStyle(primaryForeground)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: settings.terminalSurfaceBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(dividerColor)
                .frame(width: 1)
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
