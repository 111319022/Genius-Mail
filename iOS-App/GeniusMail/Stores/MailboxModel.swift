import Foundation
import Observation

enum Folder: String, Hashable {
    case inbox, sent, starred

    var title: String {
        switch self {
        case .inbox: "收件匣"
        case .sent: "已寄出"
        case .starred: "星號郵件"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .sent: "paperplane"
        case .starred: "star"
        }
    }

    var emptyText: String {
        switch self {
        case .inbox: "收件匣沒有郵件"
        case .sent: "還沒有寄出的郵件"
        case .starred: "加上星號的郵件會出現在這裡"
        }
    }
}

/// 信件在详细页或其他地方被修改时，用来同步列表
enum MailChange {
    case read(Int)
    case star(Int, Bool)
    case deleted([Int])
}

@Observable
final class MailboxModel {
    let folder: Folder
    var keyword: String?

    var mails: [Mail] = []
    var total = 0
    var isLoading = false
    var isLoadingMore = false
    var reachedEnd = false
    var error: String?
    var hasLoaded = false
    var path: [MailRoute] = []

    private let api = APIClient.shared
    private let pageSize = 30
    private var loadToken = UUID()

    init(folder: Folder, keyword: String? = nil) {
        self.folder = folder
        self.keyword = keyword
    }

    func refresh(session: Session) async {
        let token = UUID()
        loadToken = token
        isLoading = true
        defer { if loadToken == token { isLoading = false } }

        do {
            let page = try await fetch(session: session, cursor: 0)
            guard loadToken == token else { return }
            mails = page.list
            total = page.total
            reachedEnd = page.list.count < pageSize
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            guard loadToken == token else { return }
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    func loadMoreIfNeeded(current mail: Mail, session: Session) async {
        guard !reachedEnd, !isLoadingMore, !isLoading,
              let index = mails.firstIndex(where: { $0.id == mail.id }),
              index >= mails.count - 8,
              let cursor = mails.last?.emailId else { return }

        let token = loadToken
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetch(session: session, cursor: cursor)
            guard loadToken == token else { return }
            let existing = Set(mails.map(\.id))
            mails.append(contentsOf: page.list.filter { !existing.contains($0.id) })
            reachedEnd = page.list.count < pageSize
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 前景轮询：只抓比目前最新一封更新的收件
    func pollLatest(session: Session) async -> Int {
        guard folder == .inbox, keyword == nil, hasLoaded, !isLoading else { return 0 }
        let scope = session.scope
        let newest = mails.first?.emailId ?? 0
        guard let list = try? await api.latest(after: newest, accountId: scope.accountId, allReceive: scope.allReceive) else { return 0 }
        let existing = Set(mails.map(\.id))
        let fresh = list.filter { !existing.contains($0.id) }.sorted { $0.emailId > $1.emailId }
        guard !fresh.isEmpty else { return 0 }
        mails.insert(contentsOf: fresh, at: 0)
        total += fresh.count
        return fresh.count
    }

    private func fetch(session: Session, cursor: Int) async throws -> MailPage {
        let scope = session.scope
        switch folder {
        case .inbox, .sent:
            return try await api.mails(type: folder == .inbox ? 0 : 1, accountId: scope.accountId, allReceive: scope.allReceive,
                                       cursor: cursor, size: pageSize, keyword: keyword)
        case .starred:
            let list = try await api.starred(cursor: cursor, size: pageSize)
            return MailPage(list: list, total: list.count)
        }
    }

    // MARK: - 操作

    func apply(_ change: MailChange) {
        switch change {
        case .read(let id):
            if let i = mails.firstIndex(where: { $0.id == id }) { mails[i].unread = 1 }
        case .star(let id, let starred):
            if let i = mails.firstIndex(where: { $0.id == id }) {
                mails[i].isStar = starred ? 1 : 0
                if folder == .starred && !starred { mails.remove(at: i) }
            }
        case .deleted(let ids):
            let set = Set(ids)
            let before = mails.count
            mails.removeAll { set.contains($0.id) }
            total -= before - mails.count
        }
    }

    func markRead(_ ids: [Int], session: Session) async throws {
        let unread = ids.filter { id in mails.first { $0.id == id }?.isUnread ?? true }
        guard !unread.isEmpty else { return }
        unread.forEach { apply(.read($0)) }
        try await api.markRead(unread)
        await session.refreshUnread()
    }

    func toggleStar(_ mail: Mail) async throws {
        let target = !mail.isStarred
        apply(.star(mail.id, target))
        do {
            try await api.setStar(mail.id, starred: target)
        } catch {
            apply(.star(mail.id, !target))
            throw error
        }
    }

    func delete(_ ids: [Int], session: Session) async throws {
        let backup = mails
        apply(.deleted(ids))
        do {
            try await api.deleteMails(ids)
            await session.refreshUnread()
        } catch {
            mails = backup
            throw error
        }
    }
}
