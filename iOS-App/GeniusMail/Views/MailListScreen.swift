import SwiftUI

struct MailListScreen: View {
    @Bindable var model: MailboxModel
    var onChange: (MailChange) -> Void

    @Environment(Session.self) private var session
    @Environment(Composer.self) private var composer
    @Environment(PushManager.self) private var push

    @State private var selection = Set<Int>()
    @State private var editMode: EditMode = .inactive
    @State private var errorMessage: String?
    @State private var didAppear = false

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack(path: $model.path) {
            MailList(model: model, selection: $selection, onChange: onChange, onError: { errorMessage = $0 })
                .environment(\.editMode, $editMode)
                .navigationTitle(model.folder.title)
                .navigationSubtitle(model.folder == .starred ? "" : session.scopeTitle)
                .toolbar { toolbar }
                .toolbar(isEditing ? .hidden : .automatic, for: .tabBar)
                .navigationDestination(for: MailRoute.self) { route in
                    MailDetailView(route: route, onChange: onChange)
                }
        }
        .task(id: session.selectedAccountId) {
            // 切换信箱时重新载入（星号列表不分信箱）
            if model.folder != .starred || !model.hasLoaded {
                await model.refresh(session: session)
            }
        }
        .onAppear {
            // 第一次出现由上面的 task 载入；之后（例如星号列表被标记为过期）才在这里重新整理
            defer { didAppear = true }
            if didAppear && !model.hasLoaded && !model.isLoading {
                Task { await model.refresh(session: session) }
            }
        }
        .alert("操作失敗", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button(selection.count == model.mails.count ? "取消全選" : "全選") {
                    if selection.count == model.mails.count {
                        selection.removeAll()
                    } else {
                        selection = Set(model.mails.map(\.id))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成", role: .confirm) {
                    withAnimation { editMode = .inactive }
                    selection.removeAll()
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if model.folder == .inbox {
                    Button("標為已讀", systemImage: "envelope.open") {
                        let ids = Array(selection)
                        Task {
                            do {
                                try await model.markRead(ids, session: session)
                                ids.forEach { onChange(.read($0)) }
                                finishEditing()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(selection.isEmpty)
                }
                Spacer()
                Text(selection.isEmpty ? "選取郵件" : "已選取 \(selection.count) 封")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刪除", systemImage: "trash", role: .destructive) {
                    let ids = Array(selection)
                    Task {
                        do {
                            try await model.delete(ids, session: session)
                            onChange(.deleted(ids))
                            finishEditing()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                .disabled(selection.isEmpty)
            }
        } else {
            if model.folder != .starred && session.accounts.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("選取", systemImage: "checkmark.circle") {
                    withAnimation { editMode = .active }
                }
                .disabled(model.mails.isEmpty)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("撰寫", systemImage: "square.and.pencil") {
                    composer.new(accountId: session.selectedAccountId)
                }
            }
        }
    }

    private func finishEditing() {
        selection.removeAll()
        withAnimation { editMode = .inactive }
    }
}

/// 可重复使用的信件列表（收件匣、搜寻结果共用）
struct MailList: View {
    @Bindable var model: MailboxModel
    @Binding var selection: Set<Int>
    var onChange: (MailChange) -> Void
    var onError: (String) -> Void

    @Environment(Session.self) private var session
    @Environment(Composer.self) private var composer
    @Environment(PushManager.self) private var push

    var body: some View {
        List(selection: $selection) {
            ForEach(model.mails) { mail in
                NavigationLink(value: MailRoute(emailId: mail.emailId, preview: mail)) {
                    MailRow(mail: mail, folder: model.folder, accountLabel: accountLabel(for: mail))
                }
                .listRowInsets(.init(top: 10, leading: 16, bottom: 10, trailing: 16))
                .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(mail) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("刪除", systemImage: "trash", role: .destructive) { delete(mail) }
                }
                .contextMenu { contextMenu(mail) }
                .task { await model.loadMoreIfNeeded(current: mail, session: session) }
            }

            if model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if model.reachedEnd && model.mails.count > 12 {
                Text("共 \(model.folder == .starred ? model.mails.count : max(model.total, model.mails.count)) 封郵件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await model.refresh(session: session)
            await session.refreshUnread()
        }
        .overlay { overlay }
    }

    @ViewBuilder
    private var overlay: some View {
        if model.mails.isEmpty {
            if !model.hasLoaded {
                ProgressView()
            } else if let error = model.error {
                ContentUnavailableView {
                    Label("無法載入", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重試") { Task { await model.refresh(session: session) } }
                        .buttonStyle(.glass)
                }
            } else if model.keyword != nil {
                ContentUnavailableView.search(text: model.keyword ?? "")
            } else {
                ContentUnavailableView(model.folder.emptyText, systemImage: model.folder.systemImage)
            }
        }
    }

    private func accountLabel(for mail: Mail) -> String? {
        guard session.showsAccountColumn, mail.isReceived else { return nil }
        return mail.toEmail.isEmpty ? session.account(for: mail.accountId)?.email : mail.toEmail
    }

    @ViewBuilder
    private func leadingActions(_ mail: Mail) -> some View {
        if mail.isUnread {
            Button("已讀", systemImage: "envelope.open") {
                Task {
                    do {
                        try await model.markRead([mail.id], session: session)
                        onChange(.read(mail.id))
                    } catch { onError(error.localizedDescription) }
                }
            }
            .tint(.blue)
        }
        Button(mail.isStarred ? "取消星號" : "星號", systemImage: mail.isStarred ? "star.slash" : "star") {
            toggleStar(mail)
        }
        .tint(.yellow)
    }

    @ViewBuilder
    private func contextMenu(_ mail: Mail) -> some View {
        if mail.hasCode {
            Button("複製驗證碼 \(mail.code)", systemImage: "key") {
                UIPasteboard.general.string = mail.code
                push.showToast("已複製驗證碼 \(mail.code)")
            }
        }
        if mail.isReceived {
            Button("回覆", systemImage: "arrowshape.turn.up.left") { composer.reply(to: mail) }
        }
        Button("轉寄", systemImage: "arrowshape.turn.up.right") { composer.forward(mail) }
        Divider()
        if mail.isUnread {
            Button("標為已讀", systemImage: "envelope.open") {
                Task {
                    try? await model.markRead([mail.id], session: session)
                    onChange(.read(mail.id))
                }
            }
        }
        Button(mail.isStarred ? "取消星號" : "加上星號", systemImage: mail.isStarred ? "star.slash" : "star") {
            toggleStar(mail)
        }
        Button("複製寄件人地址", systemImage: "at") {
            UIPasteboard.general.string = mail.isReceived ? mail.sendEmail : mail.recipients.first?.address
        }
        Divider()
        Button("刪除", systemImage: "trash", role: .destructive) { delete(mail) }
    }

    private func toggleStar(_ mail: Mail) {
        Task {
            do {
                try await model.toggleStar(mail)
                onChange(.star(mail.id, !mail.isStarred))
            } catch { onError(error.localizedDescription) }
        }
    }

    private func delete(_ mail: Mail) {
        Task {
            do {
                try await model.delete([mail.id], session: session)
                onChange(.deleted([mail.id]))
            } catch { onError(error.localizedDescription) }
        }
    }
}

struct MailRow: View {
    let mail: Mail
    let folder: Folder
    var accountLabel: String?

    private var title: String {
        mail.isReceived ? mail.senderName : "寄給 " + mail.recipientSummary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                AvatarView(name: mail.isReceived ? mail.name : mail.recipients.first?.name ?? "",
                           email: mail.isReceived ? mail.sendEmail : mail.recipients.first?.address ?? mail.toEmail)
                if mail.isUnread {
                    Circle()
                        .fill(.blue)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .offset(x: -3, y: -3)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.body.weight(mail.isUnread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if mail.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(MailDate.short(mail.date))
                        .font(.caption)
                        .foregroundStyle(mail.isUnread ? Color.accentColor : .secondary)
                }

                Text(mail.displaySubject)
                    .font(.subheadline.weight(mail.isUnread ? .semibold : .regular))
                    .foregroundStyle(mail.isUnread ? .primary : .secondary)
                    .lineLimit(1)

                if !mail.preview.isEmpty {
                    Text(mail.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if mail.hasCode || accountLabel != nil || mail.statusLabel != nil {
                    HStack(spacing: 6) {
                        if mail.hasCode {
                            CodeChip(code: mail.code)
                        }
                        if let status = mail.statusLabel {
                            Text(status.text)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(status.isError ? .red : .secondary)
                                .background((status.isError ? Color.red : Color.secondary).opacity(0.12), in: .capsule)
                        }
                        if let accountLabel {
                            Text(accountLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
