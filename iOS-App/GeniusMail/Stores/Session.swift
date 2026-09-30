import Foundation
import Observation
import UserNotifications

/// 登录状态、使用者资料、信箱清单与目前选择的信箱
@Observable
final class Session {
    enum Phase { case launching, loggedOut, loggedIn }

    var phase: Phase = .launching
    var user: UserInfo?
    var config: WebsiteConfig?
    var accounts: [Account] = []
    var unreadCount = 0

    /// nil 代表「所有信箱」
    var selectedAccountId: Int? {
        didSet {
            if let selectedAccountId {
                UserDefaults.standard.set(selectedAccountId, forKey: "selectedAccountId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedAccountId")
            }
        }
    }

    let api = APIClient.shared

    init() {
        let saved = UserDefaults.standard.integer(forKey: "selectedAccountId")
        selectedAccountId = saved == 0 ? nil : saved
        api.onUnauthorized = { [weak self] in
            self?.handleUnauthorized()
        }
    }

    // MARK: - 信箱范围

    var selectedAccount: Account? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.accountId == selectedAccountId }
    }

    var primaryAccount: Account? {
        accounts.first { $0.email.caseInsensitiveCompare(user?.email ?? "") == .orderedSame } ?? accounts.first
    }

    /// 呼叫 /email/list 用的参数：「所有信箱」使用 allReceive=1
    var scope: (accountId: Int, allReceive: Bool) {
        if let selectedAccount { return (selectedAccount.accountId, false) }
        return (primaryAccount?.accountId ?? 0, true)
    }

    var scopeTitle: String {
        selectedAccount?.displayName ?? "所有信箱"
    }

    var showsAccountColumn: Bool { selectedAccount == nil && accounts.count > 1 }

    func account(for id: Int) -> Account? {
        accounts.first { $0.accountId == id }
    }

    // MARK: - 生命周期

    func bootstrap() async {
        guard api.token != nil else {
            phase = .loggedOut
            return
        }
        do {
            try await loadProfile()
            phase = .loggedIn
            PushManager.shared.registerIfAuthorized()
        } catch APIError.unauthorized {
            phase = .loggedOut
        } catch {
            // 网路异常时仍进入主画面，稍后可下拉重新整理
            phase = .loggedIn
        }
    }

    func login(email: String, password: String) async throws {
        let token = try await api.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        api.token = token
        try await loadProfile()
        selectedAccountId = nil
        phase = .loggedIn
        await PushManager.shared.requestAuthorization()
    }

    func logout() async {
        await PushManager.shared.unregister()
        let _: Empty? = try? await api.delete("/logout")
        clearLocalState()
    }

    private func handleUnauthorized() {
        guard phase == .loggedIn else { return }
        clearLocalState()
    }

    private func clearLocalState() {
        api.token = nil
        user = nil
        accounts = []
        selectedAccountId = nil
        unreadCount = 0
        UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
        phase = .loggedOut
    }

    func loadProfile() async throws {
        async let userTask: UserInfo = api.get("/my/loginUserInfo")
        async let configTask: WebsiteConfig = api.get("/setting/websiteConfig")
        user = try await userTask
        config = try? await configTask
        try await reloadAccounts()
        await refreshUnread()
    }

    func reloadAccounts() async throws {
        var all: [Account] = []
        var cursorId = 0
        var lastSort: Int?
        // /account/list 每页最多 30 笔，以 sort + accountId 作为游标
        while true {
            let page: [Account] = try await api.get("/account/list", query: ["accountId": cursorId, "size": 30, "lastSort": lastSort])
            all.append(contentsOf: page)
            guard page.count == 30, let last = page.last else { break }
            cursorId = last.accountId
            lastSort = last.sort
        }
        accounts = all
        if let selectedAccountId, !all.contains(where: { $0.accountId == selectedAccountId }) {
            self.selectedAccountId = nil
        }
    }

    func refreshUnread() async {
        guard let count = try? await api.unreadCount() else { return }
        unreadCount = count
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
