import SwiftUI
import SafariServices

struct MailDetailView: View {
    let route: MailRoute
    var onChange: (MailChange) -> Void

    @Environment(Session.self) private var session
    @Environment(Composer.self) private var composer
    @Environment(PushManager.self) private var push
    @Environment(\.dismiss) private var dismiss

    @State private var mail: Mail?
    @State private var isLoading = true
    @State private var error: String?
    @State private var bodyHeight: CGFloat = 120
    @State private var showDetails = false
    @State private var safariURL: URL?
    @State private var confirmDelete = false

    private var shown: Mail? { mail ?? route.preview }

    var body: some View {
        ScrollView {
            if let shown {
                VStack(alignment: .leading, spacing: 16) {
                    header(shown)

                    if shown.hasCode {
                        CodeChip(code: shown.code, large: true)
                    }

                    if let status = shown.statusLabel, status.isError, !shown.message.isEmpty {
                        Label(Self.bounceMessage(shown.message), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.1), in: .rect(cornerRadius: 12))
                    }

                    Divider()

                    content
                }
                .padding()
            } else if let error {
                ContentUnavailableView("無法開啟郵件", systemImage: "envelope.badge.shield.half.filled", description: Text(error))
                    .padding(.top, 80)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .task(id: route.emailId) { await load() }
        .sheet(item: $safariURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        .confirmationDialog("刪除這封郵件？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("刪除", role: .destructive) { Task { await delete() } }
        }
    }

    // MARK: - 区块

    private func header(_ mail: Mail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mail.displaySubject)
                .font(.title2.bold())
                .textSelection(.enabled)

            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: mail.isReceived ? mail.name : mail.recipients.first?.name ?? "",
                           email: mail.isReceived ? mail.sendEmail : mail.recipients.first?.address ?? "",
                           size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(mail.senderName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text(MailDate.short(mail.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        withAnimation(.snappy) { showDetails.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showDetails ? "隱藏詳細資訊" : "寄至 \(mail.isReceived ? (mail.toEmail.isEmpty ? mail.recipientSummary : mail.toEmail) : mail.recipientSummary)")
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .rotationEffect(.degrees(showDetails ? 180 : 0))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showDetails {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("寄件人", mail.name.isEmpty ? mail.sendEmail : "\(mail.name) <\(mail.sendEmail)>")
                    detailRow("收件人", mail.recipients.isEmpty ? mail.toEmail : mail.recipients.map(\.display).joined(separator: "\n"))
                    if !mail.ccList.isEmpty {
                        detailRow("副本", mail.ccList.map(\.display).joined(separator: "\n"))
                    }
                    detailRow("日期", MailDate.full(mail.date))
                }
                .font(.footnote)
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let mail {
            let plain = mail.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            MailBodyView(html: plain ? mail.text : mail.content, isPlainText: plain, height: $bodyHeight) { url in
                open(url)
            }
            .frame(height: bodyHeight)
            .padding(plain ? 0 : 8)
            .background(plain ? Color.clear : Color.white, in: .rect(cornerRadius: 12))

            if !mail.visibleAttachments.isEmpty {
                AttachmentSection(attachments: mail.visibleAttachments)
            }
        } else if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 40)
        } else if let error {
            Text(error).foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let mail = shown {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if mail.isReceived {
                        Button("複製寄件人地址", systemImage: "at") {
                            UIPasteboard.general.string = mail.sendEmail
                            push.showToast("已複製 \(mail.sendEmail)")
                        }
                        Button("寫信給寄件人", systemImage: "square.and.pencil") {
                            composer.new(accountId: mail.accountId, to: [mail.sendEmail])
                        }
                    }
                    if let text = self.mail?.text, !text.isEmpty {
                        ShareLink(item: "\(mail.displaySubject)\n\n\(text)") {
                            Label("分享內容", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }

            ToolbarItem(placement: .bottomBar) {
                Button("刪除", systemImage: "trash") { confirmDelete = true }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button(mail.isStarred ? "取消星號" : "星號", systemImage: mail.isStarred ? "star.fill" : "star") {
                    Task { await toggleStar() }
                }
                .tint(mail.isStarred ? .yellow : nil)
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    if mail.isReceived {
                        Button("回覆", systemImage: "arrowshape.turn.up.left") { composer.reply(to: mail) }
                        if mail.recipients.count + mail.ccList.count > 1 {
                            Button("全部回覆", systemImage: "arrowshape.turn.up.left.2") { composer.reply(to: mail, all: true) }
                        }
                    }
                    Button("轉寄", systemImage: "arrowshape.turn.up.right") { composer.forward(mail) }
                } label: {
                    Label("回覆", systemImage: "arrowshape.turn.up.left")
                } primaryAction: {
                    if mail.isReceived { composer.reply(to: mail) } else { composer.forward(mail) }
                }
            }
        }
    }

    // MARK: - 动作

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var loaded = try await APIClient.shared.detail(route.emailId)
            if loaded.isUnread {
                try? await APIClient.shared.markRead([loaded.emailId])
                loaded.unread = 1
                onChange(.read(loaded.emailId))
                await session.refreshUnread()
            }
            mail = loaded
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleStar() async {
        guard var current = shown else { return }
        let target = !current.isStarred
        current.isStar = target ? 1 : 0
        mail = current
        do {
            try await APIClient.shared.setStar(current.emailId, starred: target)
            onChange(.star(current.emailId, target))
        } catch {
            current.isStar = target ? 0 : 1
            mail = current
            push.showToast(error.localizedDescription)
        }
    }

    private func delete() async {
        guard let id = shown?.emailId else { return }
        do {
            try await APIClient.shared.deleteMails([id])
            onChange(.deleted([id]))
            await session.refreshUnread()
            dismiss()
        } catch {
            push.showToast(error.localizedDescription)
        }
    }

    private func open(_ url: URL) {
        switch url.scheme?.lowercased() {
        case "mailto":
            composer.open(mailto: url)
        case "http", "https":
            safariURL = url
        default:
            UIApplication.shared.open(url)
        }
    }

    private static func bounceMessage(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String {
            return message
        }
        return raw
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
