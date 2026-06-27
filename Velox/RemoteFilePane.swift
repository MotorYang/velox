import SwiftUI

struct RemoteFilePane: View {
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
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
                .overlay(.white.opacity(0.08))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sessionManager.remoteFiles) { file in
                        HStack(spacing: 9) {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(file.isDirectory ? .yellow.opacity(0.82) : .white.opacity(0.56))
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
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.048, green: 0.052, blue: 0.054))
        .drawingGroup(opaque: true)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(width: 1)
        }
    }
}
