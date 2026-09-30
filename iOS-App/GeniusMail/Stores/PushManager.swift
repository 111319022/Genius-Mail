import Foundation
import Observation
import UIKit
import UserNotifications

/// APNs 注册、通知动作、点击通知后的导向
@Observable
final class PushManager {
    static let shared = PushManager()

    enum Category {
        static let email = "EMAIL"
        static let emailCode = "EMAIL_CODE"
    }

    enum Action {
        static let markRead = "MARK_READ"
        static let delete = "DELETE"
        static let copyCode = "COPY_CODE"
    }

    var authorization: UNAuthorizationStatus = .notDetermined
    var deviceToken: String?
    var lastError: String?

    /// 点击通知后要打开的信件
    var pendingEmailId: Int?
    /// 前景收到推播时递增，让收件匣自动刷新
    var receivedPushCount = 0
    /// 画面顶部的短暂提示
    var toast: String?

    private init() {}

    /// 实机开发版走 sandbox，TestFlight / App Store 版走 production
    var environment: String {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1) else { return "production" }
        return text.range(of: "<key>aps-environment</key>\\s*<string>development</string>", options: .regularExpression) != nil
            ? "sandbox" : "production"
        #endif
    }

    func registerCategories() {
        let markRead = UNNotificationAction(identifier: Action.markRead, title: "標為已讀", options: [], icon: .init(systemImageName: "envelope.open"))
        let delete = UNNotificationAction(identifier: Action.delete, title: "刪除", options: [.destructive, .authenticationRequired], icon: .init(systemImageName: "trash"))
        let copy = UNNotificationAction(identifier: Action.copyCode, title: "複製驗證碼", options: [], icon: .init(systemImageName: "doc.on.doc"))

        let email = UNNotificationCategory(identifier: Category.email, actions: [markRead, delete], intentIdentifiers: [], options: [])
        let code = UNNotificationCategory(identifier: Category.emailCode, actions: [copy, markRead, delete], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([email, code])
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorization()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func registerIfAuthorized() {
        Task {
            await refreshAuthorization()
            if authorization == .authorized || authorization == .provisional {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { await uploadToken() }
    }

    func didFailToRegister(_ error: Error) {
        lastError = error.localizedDescription
    }

    func uploadToken() async {
        guard let deviceToken, APIClient.shared.token != nil else { return }
        do {
            let _: Empty = try await APIClient.shared.post("/push/register", body: [
                "deviceToken": deviceToken,
                "environment": environment,
                "deviceName": UIDevice.current.name
            ])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unregister() async {
        guard let deviceToken else { return }
        let _: Empty? = try? await APIClient.shared.delete("/push/unregister", query: ["deviceToken": deviceToken])
    }

    // MARK: - 通知回应

    func handle(response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let emailId = (info["emailId"] as? Int) ?? Int("\(info["emailId"] ?? "")")
        let code = info["code"] as? String ?? ""

        switch response.actionIdentifier {
        case Action.copyCode:
            UIPasteboard.general.string = code
            if let emailId { try? await APIClient.shared.markRead([emailId]) }
        case Action.markRead:
            if let emailId { try? await APIClient.shared.markRead([emailId]) }
        case Action.delete:
            if let emailId { try? await APIClient.shared.deleteMails([emailId]) }
        case UNNotificationDefaultActionIdentifier:
            pendingEmailId = emailId
        default:
            break
        }

        if response.actionIdentifier != UNNotificationDefaultActionIdentifier,
           let count = try? await APIClient.shared.unreadCount() {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
        receivedPushCount += 1
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }
}
