import Foundation

struct Mail: Identifiable, Hashable, Decodable {
    let emailId: Int
    var sendEmail: String
    var name: String
    var accountId: Int
    var subject: String
    var code: String
    var text: String
    var content: String
    var recipient: String
    var cc: String
    var toEmail: String
    var toName: String
    var type: Int
    var status: Int
    var message: String
    var unread: Int
    var createTime: String
    var isStar: Int
    var listText: String
    var attList: [Attachment]?

    var id: Int { emailId }

    enum CodingKeys: String, CodingKey {
        case emailId, sendEmail, name, accountId, subject, code, text, content, recipient, cc
        case toEmail, toName, type, status, message, unread, createTime, isStar, listText, attList
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emailId = try c.decode(Int.self, forKey: .emailId)
        sendEmail = c.string(.sendEmail)
        name = c.string(.name)
        accountId = c.int(.accountId)
        subject = c.string(.subject)
        code = c.string(.code)
        text = c.string(.text)
        content = c.string(.content)
        recipient = c.string(.recipient)
        cc = c.string(.cc)
        toEmail = c.string(.toEmail)
        toName = c.string(.toName)
        type = c.int(.type)
        status = c.int(.status)
        message = c.string(.message)
        unread = c.int(.unread, default: 1)
        createTime = c.string(.createTime)
        isStar = c.int(.isStar)
        listText = c.string(.listText)
        attList = try? c.decodeIfPresent([Attachment].self, forKey: .attList)
    }

    var isReceived: Bool { type == 0 }
    var isUnread: Bool { isReceived && unread == 0 }
    var isStarred: Bool { isStar == 1 }
    var hasCode: Bool { !code.isEmpty }

    var senderName: String {
        if !name.isEmpty { return name }
        return sendEmail.split(separator: "@").first.map(String.init) ?? sendEmail
    }

    var displaySubject: String { subject.isEmpty ? "（無主旨）" : subject }

    var preview: String {
        let source = listText.isEmpty ? text : listText
        return source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var date: Date? { MailDate.parse(createTime) }

    var recipients: [MailAddress] { MailAddress.parseList(recipient) }
    var ccList: [MailAddress] { MailAddress.parseList(cc) }

    /// 已寄出信件列表中显示的对象
    var recipientSummary: String {
        let list = recipients
        guard let first = list.first else { return toEmail }
        let head = first.name.isEmpty ? first.address : first.name
        return list.count > 1 ? "\(head) 等 \(list.count) 人" : head
    }

    var visibleAttachments: [Attachment] {
        (attList ?? []).filter { $0.type != 1 }
    }

    var statusLabel: (text: String, isError: Bool)? {
        guard !isReceived else { return nil }
        switch status {
        case 1: return ("已送出", false)
        case 2: return ("已送達", false)
        case 3: return ("被退回", true)
        case 4: return ("被標為垃圾郵件", true)
        case 5: return ("延遲中", false)
        case 8: return ("傳送失敗", true)
        default: return nil
        }
    }
}

struct MailAddress: Hashable, Decodable {
    var address: String
    var name: String

    enum CodingKeys: String, CodingKey { case address, name }

    init(address: String, name: String = "") {
        self.address = address
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = c.string(.address)
        name = c.string(.name)
    }

    static func parseList(_ json: String) -> [MailAddress] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([MailAddress].self, from: data) else { return [] }
        return list.filter { !$0.address.isEmpty }
    }

    var display: String { name.isEmpty ? address : "\(name) <\(address)>" }
}

struct Attachment: Identifiable, Hashable, Decodable {
    let attId: Int
    var key: String
    var filename: String
    var mimeType: String
    var size: Int
    var type: Int

    var id: Int { attId }

    enum CodingKeys: String, CodingKey { case attId, key, filename, mimeType, size, type }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attId = c.int(.attId)
        key = c.string(.key)
        filename = c.string(.filename)
        mimeType = c.string(.mimeType)
        size = c.int(.size)
        type = c.int(.type)
    }

    var displayName: String { filename.isEmpty ? (key.split(separator: "/").last.map(String.init) ?? "附件") : filename }

    var systemImage: String {
        let ext = (displayName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "svg": return "photo"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "gz", "tar": return "doc.zipper"
        case "mp4", "mov", "m4v", "avi": return "film"
        case "mp3", "m4a", "wav", "aac": return "waveform"
        case "doc", "docx", "pages", "txt", "rtf", "md": return "doc.text"
        case "xls", "xlsx", "csv", "numbers": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "ics": return "calendar"
        default: return "doc"
        }
    }
}

struct Account: Identifiable, Hashable, Decodable {
    let accountId: Int
    var email: String
    var name: String
    var allReceive: Int
    var sort: Int

    var id: Int { accountId }

    enum CodingKeys: String, CodingKey { case accountId, email, name, allReceive, sort }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = c.int(.accountId)
        email = c.string(.email)
        name = c.string(.name)
        allReceive = c.int(.allReceive)
        sort = c.int(.sort)
    }

    var displayName: String { name.isEmpty ? email : name }
}

struct UserInfo: Decodable {
    var userId: Int
    var email: String
    var name: String
    var sendCount: Int
    var role: Role?
    var permKeys: [String]

    struct Role: Decodable {
        var name: String
        var sendCount: Int
        var sendType: String
        var accountCount: Int

        enum CodingKeys: String, CodingKey { case name, sendCount, sendType, accountCount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.string(.name)
            sendCount = c.int(.sendCount)
            sendType = c.string(.sendType)
            accountCount = c.int(.accountCount)
        }
    }

    enum CodingKeys: String, CodingKey { case userId, email, name, sendCount, role, permKeys }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.int(.userId)
        email = c.string(.email)
        name = c.string(.name)
        sendCount = c.int(.sendCount)
        role = try? c.decodeIfPresent(Role.self, forKey: .role)
        permKeys = (try? c.decodeIfPresent([String].self, forKey: .permKeys)) ?? []
    }

    func can(_ perm: String) -> Bool { permKeys.contains("*") || permKeys.contains(perm) }

    var sendQuotaText: String {
        guard let role, role.sendCount > 0 else { return "無限制" }
        let unit = role.sendType == "day" ? "今日" : "總計"
        return "\(unit) \(sendCount) / \(role.sendCount)"
    }
}

struct WebsiteConfig: Decodable {
    var title: String
    var r2Domain: String
    var domainList: [String]
    var send: Int
    var addEmail: Int
    var manyEmail: Int
    var addEmailVerify: Int
    var addVerifyOpen: Bool

    enum CodingKeys: String, CodingKey { case title, r2Domain, domainList, send, addEmail, manyEmail, addEmailVerify, addVerifyOpen }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.string(.title)
        r2Domain = c.string(.r2Domain)
        domainList = (try? c.decodeIfPresent([String].self, forKey: .domainList)) ?? []
        send = c.int(.send)
        addEmail = c.int(.addEmail)
        manyEmail = c.int(.manyEmail)
        addEmailVerify = c.int(.addEmailVerify)
        addVerifyOpen = (try? c.decodeIfPresent(Bool.self, forKey: .addVerifyOpen)) ?? false
    }

    var canSend: Bool { send == 0 }
    var canAddAccount: Bool { addEmail == 0 && manyEmail == 0 }
    /// 新增信箱是否会要求 Turnstile 人机验证（App 内无法完成）
    var addAccountNeedsCaptcha: Bool { addEmailVerify == 0 || (addEmailVerify == 2 && addVerifyOpen) }
}

struct MailPage: Decodable {
    var list: [Mail]
    var total: Int

    enum CodingKeys: String, CodingKey { case list, total }

    init(list: [Mail], total: Int) {
        self.list = list
        self.total = total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = (try? c.decodeIfPresent([Mail].self, forKey: .list)) ?? []
        total = c.int(.total)
    }
}

struct PushStatus: Decodable {
    var configured: Bool
    var devices: [Device]

    struct Device: Decodable, Hashable {
        var env: String
        var name: String?
        var updateTime: String?
        var tokenSuffix: String
    }
}

struct PushTestResult: Decodable, Hashable {
    var env: String
    var name: String?
    var tokenSuffix: String
    var ok: Bool
    var reason: String?
}

struct UnreadCount: Decodable { var total: Int }
struct LoginResult: Decodable { var token: String }

// MARK: - 宽松解码：后端字段可能为 null、字符串或数字

extension KeyedDecodingContainer {
    func string(_ key: Key) -> String {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        return ""
    }

    func int(_ key: Key, default fallback: Int = 0) -> Int {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(String.self, forKey: key), let n = Int(v) { return n }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? 1 : 0 }
        return fallback
    }
}

enum MailDate {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        if let d = parser.date(from: string) { return d }
        return try? Date(string, strategy: .iso8601)
    }

    /// 列表用：今天显示时间，本周显示星期，其余显示日期
    static func short(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "昨天" }
        if let days = cal.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month().day())
        }
        return date.formatted(date: .numeric, time: .omitted)
    }

    static func full(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.year().month().day().weekday().hour().minute())
    }
}

extension Int {
    var byteSize: String { ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file) }
}
