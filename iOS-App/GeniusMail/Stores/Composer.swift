import Foundation
import Observation

struct ComposeDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var accountId: Int?
    var to: [String] = []
    var subject = ""
    var body = ""
    /// "" 新信件、"reply" 回覆、"forward" 转寄
    var sendType = ""
    /// 回覆/转寄的原始信件
    var sourceEmailId = 0
    /// 引用内容（开启撰写画面后才载入完整原文）
    var quoteHeader = ""
    var quotedHTML = ""
    var quotedText = ""

    var isEmpty: Bool {
        to.isEmpty && subject.trimmingCharacters(in: .whitespaces).isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let storeKey = "savedDraft"

    static func loadSaved() -> ComposeDraft? {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return nil }
        return try? JSONDecoder().decode(ComposeDraft.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}

/// 负责开启撰写画面（新信件、回覆、转寄、mailto 连结）
@Observable
final class Composer {
    var draft: ComposeDraft?

    func new(accountId: Int? = nil, to: [String] = []) {
        if to.isEmpty, let saved = ComposeDraft.loadSaved() {
            draft = saved
            return
        }
        draft = ComposeDraft(accountId: accountId, to: to)
    }

    func reply(to mail: Mail, all: Bool = false) {
        var to = [mail.sendEmail]
        if all {
            let own = Set([mail.toEmail.lowercased()])
            let others = (mail.recipients + mail.ccList).map(\.address).filter { !own.contains($0.lowercased()) }
            to.append(contentsOf: others)
        }
        var seen = Set<String>()
        to = to.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }

        draft = ComposeDraft(
            accountId: mail.isReceived ? mail.accountId : nil,
            to: to,
            subject: Self.prefixed(mail.subject, with: "Re:"),
            sendType: "reply",
            sourceEmailId: mail.emailId
        )
    }

    func forward(_ mail: Mail) {
        draft = ComposeDraft(
            accountId: mail.accountId == 0 ? nil : mail.accountId,
            subject: Self.prefixed(mail.subject, with: "Fwd:"),
            sendType: "forward",
            sourceEmailId: mail.emailId
        )
    }

    func open(mailto url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let address = url.absoluteString
            .replacingOccurrences(of: "mailto:", with: "")
            .components(separatedBy: "?").first?
            .removingPercentEncoding ?? ""
        var next = ComposeDraft(to: address.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        next.subject = components?.queryItems?.first { $0.name.lowercased() == "subject" }?.value ?? ""
        next.body = components?.queryItems?.first { $0.name.lowercased() == "body" }?.value ?? ""
        draft = next
    }

    private static func prefixed(_ subject: String, with prefix: String) -> String {
        subject.lowercased().hasPrefix(prefix.lowercased()) ? subject : "\(prefix) \(subject)"
    }
}

/// 最近寄送过的收件人，用于自动完成
enum RecentRecipients {
    private static let key = "recentRecipients"

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ addresses: [String]) {
        var list = all.filter { item in !addresses.contains { $0.caseInsensitiveCompare(item) == .orderedSame } }
        list.insert(contentsOf: addresses, at: 0)
        UserDefaults.standard.set(Array(list.prefix(60)), forKey: key)
    }
}
