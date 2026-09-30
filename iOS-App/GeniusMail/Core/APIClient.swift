import Foundation

enum APIError: LocalizedError {
    case server(code: Int, message: String)
    case unauthorized(String)
    case invalidServer
    case badResponse

    var errorDescription: String? {
        switch self {
        case .server(_, let message): return message.replacingOccurrences(of: "<br/>", with: "\n")
        case .unauthorized(let message): return message.isEmpty ? "登入已過期，請重新登入" : message
        case .invalidServer: return "伺服器網址不正確"
        case .badResponse: return "伺服器回應格式錯誤"
        }
    }
}

struct Empty: Decodable {}

/// 对应 Worker 的 `/api/*`，回应统一为 `{ code, message, data }`
final class APIClient {
    static let shared = APIClient()

    static let defaultServer = "https://mail.rayisgenius.cc"

    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    var token: String? {
        didSet { Keychain.set(token, for: "token") }
    }

    /// 收到 401 时通知 Session 回到登录页
    var onUnauthorized: (() -> Void)?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? Self.defaultServer
        token = Keychain.get("token")
    }

    var baseURL: URL? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    /// 附件、内嵌图片的完整网址（后端 r2Domain 为空时由 Worker 直接提供 /attachments/*）
    func fileURL(key: String, r2Domain: String) -> URL? {
        if key.hasPrefix("http") { return URL(string: key) }
        var domain = r2Domain.trimmingCharacters(in: .whitespaces)
        if domain.isEmpty {
            return baseURL?.appending(path: key)
        }
        if !domain.hasPrefix("http") { domain = "https://" + domain }
        while domain.hasSuffix("/") { domain.removeLast() }
        return URL(string: domain + "/" + key)
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String, query: [String: Any?] = [:]) async throws -> T {
        try await request("GET", path, query: query, body: nil)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await request("POST", path, query: [:], body: body)
    }

    func put<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await request("PUT", path, query: [:], body: body)
    }

    func delete<T: Decodable>(_ path: String, query: [String: Any?] = [:]) async throws -> T {
        try await request("DELETE", path, query: query, body: nil)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: Any?], body: [String: Any]?, timeout: TimeInterval = 60) async throws -> T {
        guard let base = baseURL, var components = URLComponents(url: base.appending(path: "api" + path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidServer
        }

        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: "\(value)")
        }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw APIError.invalidServer }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = body?["attachments"] != nil ? 180 : timeout
        req.setValue(token ?? "", forHTTPHeaderField: "Authorization")
        req.setValue("zh", forHTTPHeaderField: "accept-language")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            onUnauthorized?()
            throw APIError.unauthorized("")
        }

        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            #if DEBUG
            print("Decode \(path) failed:", error, String(data: data.prefix(500), encoding: .utf8) ?? "")
            #endif
            throw APIError.badResponse
        }

        if envelope.code == 401 {
            onUnauthorized?()
            throw APIError.unauthorized(envelope.message ?? "")
        }

        guard envelope.code == 200 else {
            throw APIError.server(code: envelope.code, message: envelope.message ?? "未知錯誤 (\(envelope.code))")
        }

        if let data = envelope.data { return data }
        if let empty = Empty() as? T { return empty }
        throw APIError.badResponse
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String?
        let data: T?

        enum CodingKeys: String, CodingKey { case code, message, data }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            message = try? c.decodeIfPresent(String.self, forKey: .message)
            // 失败回应里没有 data，成功但 data 为 null 时也不应报错
            data = code == 200 ? try c.decodeIfPresent(T.self, forKey: .data) : nil
        }
    }
}

// MARK: - Endpoints

extension APIClient {
    func login(email: String, password: String) async throws -> String {
        let result: LoginResult = try await post("/login", body: ["email": email, "password": password])
        return result.token
    }

    func mails(type: Int, accountId: Int, allReceive: Bool, cursor: Int, size: Int = 30, keyword: String? = nil) async throws -> MailPage {
        try await get("/email/list", query: [
            "accountId": accountId,
            "allReceive": allReceive ? 1 : 0,
            "emailId": cursor,
            "timeSort": 0,
            "size": size,
            "type": type,
            "full": 0,
            "keyword": keyword
        ])
    }

    func starred(cursor: Int, size: Int = 30) async throws -> [Mail] {
        let page: MailPage = try await get("/star/list", query: ["emailId": cursor, "size": size, "full": 0])
        return page.list
    }

    func latest(after emailId: Int, accountId: Int, allReceive: Bool) async throws -> [Mail] {
        try await get("/email/latest", query: ["emailId": emailId, "accountId": accountId, "allReceive": allReceive ? 1 : 0])
    }

    func detail(_ emailId: Int) async throws -> Mail {
        try await get("/email/detail", query: ["emailId": emailId])
    }

    func markRead(_ ids: [Int]) async throws {
        let _: Empty = try await put("/email/read", body: ["emailIds": ids])
    }

    func deleteMails(_ ids: [Int]) async throws {
        let _: Empty = try await delete("/email/delete", query: ["emailIds": ids.map(String.init).joined(separator: ",")])
    }

    func setStar(_ emailId: Int, starred: Bool) async throws {
        if starred {
            let _: Empty = try await post("/star/add", body: ["emailId": emailId])
        } else {
            let _: Empty = try await delete("/star/cancel", query: ["emailId": emailId])
        }
    }

    func unreadCount() async throws -> Int {
        let result: UnreadCount = try await get("/email/unreadCount")
        return result.total
    }
}
