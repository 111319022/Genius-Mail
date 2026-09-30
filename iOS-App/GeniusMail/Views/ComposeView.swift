import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PendingAttachment: Identifiable {
    let id = UUID()
    var filename: String
    var data: Data
    var contentType: String

    var systemImage: String {
        contentType.hasPrefix("image/") ? "photo" : contentType.hasPrefix("video/") ? "film" : "doc"
    }
}

struct ComposeView: View {
    @State private var draft: ComposeDraft
    var onSent: (Mail?) -> Void

    @Environment(Session.self) private var session
    @Environment(PushManager.self) private var push
    @Environment(\.dismiss) private var dismiss

    @State private var toInput = ""
    @State private var attachments: [PendingAttachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showDiscardDialog = false
    @State private var isLoadingQuote = false
    @State private var showQuote = false
    @FocusState private var focus: Field?

    private enum Field { case to, subject, body }

    private let maxTotalBytes = 25 * 1024 * 1024

    init(draft: ComposeDraft, onSent: @escaping (Mail?) -> Void = { _ in }) {
        _draft = State(initialValue: draft)
        self.onSent = onSent
    }

    private var fromAccount: Account? {
        if let id = draft.accountId, let account = session.account(for: id) { return account }
        return session.selectedAccount ?? session.primaryAccount
    }

    private var title: String {
        switch draft.sendType {
        case "reply": "回覆"
        case "forward": "轉寄"
        default: "新郵件"
        }
    }

    private var totalBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }

    private var canSend: Bool {
        !isSending && (!draft.to.isEmpty || toInput.isValidEmail) && fromAccount != nil
    }

    private var suggestions: [String] {
        let input = toInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !input.isEmpty else { return [] }
        return RecentRecipients.all
            .filter { $0.lowercased().contains(input) && !draft.to.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let config = session.config, !config.canSend {
                        Label("管理員已關閉寄信功能", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    fieldRow("寄件人") {
                        Menu {
                            Picker("寄件人", selection: Binding(get: { fromAccount?.accountId }, set: { draft.accountId = $0 })) {
                                ForEach(session.accounts) { account in
                                    Text(account.email).tag(Int?.some(account.accountId))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(fromAccount?.email ?? "選擇信箱")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider().padding(.leading)

                    fieldRow("收件人") {
                        recipientField
                    }

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(suggestions, id: \.self) { address in
                                Button {
                                    draft.to.append(address)
                                    toInput = ""
                                } label: {
                                    HStack {
                                        AvatarView(name: "", email: address, size: 28)
                                        Text(address).foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(.background.secondary)
                    }

                    Divider().padding(.leading)

                    fieldRow("主旨") {
                        TextField("", text: $draft.subject)
                            .focused($focus, equals: .subject)
                            .submitLabel(.next)
                            .onSubmit { focus = .body }
                    }

                    Divider()

                    TextField("輸入內容…", text: $draft.body, axis: .vertical)
                        .lineLimit(12...)
                        .focused($focus, equals: .body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if !attachments.isEmpty {
                        attachmentList
                    }

                    if !draft.sendType.isEmpty {
                        quoteSection
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .disabled(isSending)
            .overlay {
                if isSending {
                    ProgressView("寄送中…")
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .interactiveDismissDisabled(!draft.isEmpty || !attachments.isEmpty)
            .confirmationDialog("要保留這封郵件嗎？", isPresented: $showDiscardDialog, titleVisibility: .visible) {
                if draft.sendType.isEmpty {
                    Button("儲存草稿") {
                        commitInput()
                        draft.save()
                        dismiss()
                    }
                }
                Button("捨棄", role: .destructive) {
                    if draft.sendType.isEmpty { ComposeDraft.clearSaved() }
                    dismiss()
                }
                Button("繼續編輯", role: .cancel) {}
            } message: {
                if !attachments.isEmpty { Text("附件不會儲存在草稿中") }
            }
            .alert("無法寄出", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .task { await loadQuote() }
            .onAppear {
                if draft.to.isEmpty { focus = .to } else if draft.sendType == "reply" { focus = .body }
            }
        }
    }

    // MARK: - 子画面

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 56, alignment: .leading)
            content()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !draft.to.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(draft.to, id: \.self) { address in
                        recipientChip(address)
                    }
                }
            }
            TextField(draft.to.isEmpty ? "輸入電子郵件" : "新增收件人", text: $toInput)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .to)
                .submitLabel(.next)
                .onSubmit {
                    commitInput()
                    focus = .subject
                }
                .onChange(of: toInput) { _, value in
                    if value.contains(where: { ",; \n".contains($0) }) { commitInput() }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recipientChip(_ address: String) -> some View {
        Button {
            draft.to.removeAll { $0 == address }
        } label: {
            HStack(spacing: 4) {
                Text(address)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(address.isValidEmail ? Color.accentColor : .red)
            .background((address.isValidEmail ? Color.accentColor : .red).opacity(0.13), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收件人 \(address)，點兩下移除")
    }

    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("附件（\(attachments.count)）")
                Spacer()
                Text(totalBytes.byteSize)
                    .foregroundStyle(totalBytes > maxTotalBytes ? .red : .secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            ForEach(attachments) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.systemImage)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(item.filename).lineLimit(1).truncationMode(.middle)
                        Text(item.data.count.byteSize).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("移除", systemImage: "xmark.circle.fill") {
                        attachments.removeAll { $0.id == item.id }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var quoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showQuote.toggle() }
            } label: {
                HStack {
                    Image(systemName: "text.quote")
                    Text(draft.sendType == "reply" ? "引用原始郵件" : "轉寄的郵件")
                    if isLoadingQuote { ProgressView().controlSize(.small) }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showQuote ? 180 : 0))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showQuote {
                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.quoteHeader)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(draft.quotedText.isEmpty ? "（無內容）" : draft.quotedText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(30)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.tertiary).frame(width: 2)
                }
            }

            if draft.sendType == "forward" {
                Text("原始郵件的附件不會一併轉寄")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消", systemImage: "xmark", role: .close) {
                commitInput()
                if draft.isEmpty && attachments.isEmpty {
                    dismiss()
                } else {
                    showDiscardDialog = true
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("寄出", systemImage: "paperplane.fill", role: .confirm) {
                Task { await send() }
            }
            .disabled(!canSend)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                Label("照片", systemImage: "photo.on.rectangle")
            }
            Button("檔案", systemImage: "paperclip") { showFileImporter = true }
            Spacer()
        }
    }

    // MARK: - 动作

    private func commitInput() {
        let parts = toInput
            .split(whereSeparator: { ",; \n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for address in parts where !draft.to.contains(where: { $0.caseInsensitiveCompare(address) == .orderedSame }) {
            draft.to.append(address)
        }
        toInput = ""
    }

    private func loadQuote() async {
        guard draft.sourceEmailId > 0, draft.quoteHeader.isEmpty else { return }
        isLoadingQuote = true
        defer { isLoadingQuote = false }
        guard let mail = try? await APIClient.shared.detail(draft.sourceEmailId) else { return }

        let sender = mail.name.isEmpty ? mail.sendEmail : "\(mail.name) <\(mail.sendEmail)>"
        let date = MailDate.full(mail.date)
        let text = mail.text.isEmpty ? mail.preview : mail.text
        let html = mail.content.isEmpty ? text.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>") : mail.content

        if draft.accountId == nil, mail.accountId != 0 { draft.accountId = mail.accountId }

        if draft.sendType == "reply" {
            draft.quoteHeader = "於 \(date)，\(sender) 寫道："
        } else {
            let to = mail.recipients.map(\.display).joined(separator: ", ")
            draft.quoteHeader = "---------- 轉寄的郵件 ----------\n寄件人：\(sender)\n日期：\(date)\n主旨：\(mail.subject)\n收件人：\(to)"
        }
        draft.quotedHTML = html
        draft.quotedText = text
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let stamp = Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .filter(\.isNumber)
            if type?.conforms(to: .image) == true, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
                // HEIC 转成 JPEG，确保对方都能开启
                attachments.append(.init(filename: "IMG_\(stamp)_\(index + 1).jpg", data: jpeg, contentType: "image/jpeg"))
            } else {
                let ext = type?.preferredFilenameExtension ?? "mov"
                attachments.append(.init(filename: "VID_\(stamp)_\(index + 1).\(ext)", data: data, contentType: type?.preferredMIMEType ?? "application/octet-stream"))
            }
        }
        photoItems = []
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            attachments.append(.init(filename: url.lastPathComponent, data: data, contentType: mime))
        }
    }

    private func buildContent() -> (html: String, text: String) {
        let bodyHTML = draft.body.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>")
        var html = "<div>\(bodyHTML)</div>"
        var text = draft.body

        if !draft.quoteHeader.isEmpty {
            let header = draft.quoteHeader.htmlEscaped.replacingOccurrences(of: "\n", with: "<br>")
            if draft.sendType == "reply" {
                html += "<br><div style=\"color:#6b7280\">\(header)</div><blockquote style=\"margin:0 0 0 .8ex;border-left:2px solid #d1d5db;padding-left:1ex\">\(draft.quotedHTML)</blockquote>"
                let quoted = draft.quotedText.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
                text += "\n\n\(draft.quoteHeader)\n\(quoted)"
            } else {
                html += "<br><div style=\"color:#6b7280\">\(header)</div><br>\(draft.quotedHTML)"
                text += "\n\n\(draft.quoteHeader)\n\n\(draft.quotedText)"
            }
        }
        return (html, text)
    }

    private func send() async {
        commitInput()
        focus = nil

        guard let account = fromAccount else {
            errorMessage = "請選擇寄件信箱"
            return
        }
        let invalid = draft.to.filter { !$0.isValidEmail }
        guard invalid.isEmpty else {
            errorMessage = "收件人格式不正確：\(invalid.joined(separator: ", "))"
            return
        }
        guard !draft.to.isEmpty else {
            errorMessage = "請輸入收件人"
            return
        }
        guard totalBytes <= maxTotalBytes else {
            errorMessage = "附件總大小超過 25 MB"
            return
        }
        if draft.sourceEmailId > 0 && draft.quoteHeader.isEmpty {
            await loadQuote()
        }

        isSending = true
        defer { isSending = false }

        let content = buildContent()
        var body: [String: Any] = [
            "accountId": account.accountId,
            "name": account.name,
            "receiveEmail": draft.to,
            "subject": draft.subject,
            "content": content.html,
            "text": content.text,
            "sendType": draft.sendType,
            "emailId": draft.sendType == "reply" ? draft.sourceEmailId : 0,
            "manyType": NSNull()
        ]
        if !attachments.isEmpty {
            body["attachments"] = attachments.map {
                [
                    "filename": $0.filename,
                    "content": $0.data.base64EncodedString(),
                    "contentType": $0.contentType,
                    "type": $0.contentType,
                    "size": $0.data.count
                ] as [String: Any]
            }
        }

        do {
            let result: [Mail] = try await APIClient.shared.post("/email/send", body: body)
            RecentRecipients.add(draft.to)
            if draft.sendType.isEmpty { ComposeDraft.clearSaved() }
            onSent(result.first)
            push.showToast("郵件已寄出")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
