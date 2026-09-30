import SwiftUI
import QuickLook

/// 附件列表：点一下下载并以 QuickLook 预览（预览画面可直接分享、储存）
struct AttachmentSection: View {
    let attachments: [Attachment]

    @Environment(Session.self) private var session
    @State private var downloading: Set<Int> = []
    @State private var previewURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(attachments.count) 個附件", systemImage: "paperclip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(attachments) { item in
                Button {
                    Task { await preview(item) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemImage)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.primary)
                            if item.size > 0 {
                                Text(item.size.byteSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if downloading.contains(item.id) {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.background.secondary, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(downloading.contains(item.id))
            }
        }
        .quickLookPreview($previewURL)
        .alert("無法下載附件", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func preview(_ item: Attachment) async {
        guard let remote = APIClient.shared.fileURL(key: item.key, r2Domain: session.config?.r2Domain ?? "") else { return }

        let folder = FileManager.default.temporaryDirectory.appending(path: "attachments/\(item.attId)", directoryHint: .isDirectory)
        let safeName = item.displayName.replacingOccurrences(of: "/", with: "_")
        let local = folder.appending(path: safeName)

        if FileManager.default.fileExists(atPath: local.path()) {
            previewURL = local
            return
        }

        downloading.insert(item.id)
        defer { downloading.remove(item.id) }

        do {
            let (temp, response) = try await URLSession.shared.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.moveItem(at: temp, to: local)
            previewURL = local
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
