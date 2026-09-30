import SwiftUI

enum AppTab: Hashable { case inbox, sent, starred, settings, search }

/// 列表 → 详细页的导航值；preview 用来在载入完整内容前先显示标题
struct MailRoute: Hashable {
    let emailId: Int
    var preview: Mail?
}

struct MainTabView: View {
    @Environment(Session.self) private var session
    @Environment(PushManager.self) private var push
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .inbox
    @State private var inbox = MailboxModel(folder: .inbox)
    @State private var sent = MailboxModel(folder: .sent)
    @State private var starred = MailboxModel(folder: .starred)
    @State private var composer = Composer()

    var body: some View {
        @Bindable var composer = composer

        TabView(selection: $tab) {
            Tab("收件匣", systemImage: "tray", value: AppTab.inbox) {
                MailListScreen(model: inbox, onChange: broadcast)
            }
            .badge(session.unreadCount)

            Tab("已寄出", systemImage: "paperplane", value: AppTab.sent) {
                MailListScreen(model: sent, onChange: broadcast)
            }

            Tab("星號", systemImage: "star", value: AppTab.starred) {
                MailListScreen(model: starred, onChange: broadcast)
            }

            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }

            Tab(value: AppTab.search, role: .search) {
                SearchScreen(onChange: broadcast)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(composer)
        .sheet(item: $composer.draft) { draft in
            ComposeView(draft: draft) { sentMail in
                if let sentMail, sent.hasLoaded {
                    sent.mails.insert(sentMail, at: 0)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = push.toast {
                ToastView(text: toast)
            }
        }
        .animation(.snappy, value: push.toast)
        .task(id: scenePhase) {
            // 前景时每 20 秒检查新信（推播之外的保险）
            guard scenePhase == .active else { return }
            await session.refreshUnread()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if await inbox.pollLatest(session: session) > 0 {
                    await session.refreshUnread()
                }
            }
        }
        .onChange(of: push.receivedPushCount) {
            Task {
                _ = await inbox.pollLatest(session: session)
                await session.refreshUnread()
            }
        }
        .onChange(of: push.pendingEmailId, initial: true) { _, emailId in
            guard let emailId else { return }
            push.pendingEmailId = nil
            tab = .inbox
            inbox.path = [MailRoute(emailId: emailId)]
        }
    }

    /// 某个列表里的操作同步到其他列表
    private func broadcast(_ change: MailChange) {
        inbox.apply(change)
        sent.apply(change)
        starred.apply(change)
        if case .star(_, true) = change { starred.hasLoaded = false }
    }
}
