import SwiftUI

struct SearchScreen: View {
    var onChange: (MailChange) -> Void

    @Environment(Session.self) private var session

    @State private var query = ""
    @State private var scope: Folder = .inbox
    @State private var model = MailboxModel(folder: .inbox, keyword: "")
    @State private var selection = Set<Int>()
    @State private var errorMessage: String?
    @AppStorage("recentSearches") private var recentStorage = ""

    private var recents: [String] {
        recentStorage.split(separator: "\n").map(String.init)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $model.path) {
            Group {
                if trimmed.isEmpty {
                    recentList
                } else {
                    MailList(model: model, selection: $selection, onChange: onChange, onError: { errorMessage = $0 })
                }
            }
            .navigationTitle("搜尋")
            .navigationSubtitle(session.scopeTitle)
            .searchable(text: $query, prompt: "寄件人、主旨、內容")
            .searchScopes($scope) {
                Text("收件匣").tag(Folder.inbox)
                Text("已寄出").tag(Folder.sent)
            }
            .onSubmit(of: .search) { remember(trimmed) }
            .navigationDestination(for: MailRoute.self) { route in
                MailDetailView(route: route, onChange: { change in
                    model.apply(change)
                    onChange(change)
                })
            }
            .toolbar {
                if session.accounts.count > 1 {
                    ToolbarItem(placement: .topBarLeading) { AccountMenu() }
                }
            }
        }
        .task(id: "\(trimmed)|\(scope.rawValue)|\(session.selectedAccountId ?? 0)") {
            guard !trimmed.isEmpty else { return }
            // 输入时稍等再查询，避免每个字都打 API
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let next = MailboxModel(folder: scope, keyword: trimmed)
            model = next
            await next.refresh(session: session)
        }
        .alert("操作失敗", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var recentList: some View {
        if recents.isEmpty {
            ContentUnavailableView("搜尋郵件", systemImage: "magnifyingglass", description: Text("可以搜尋寄件人、收件人、主旨或內文"))
        } else {
            List {
                Section {
                    ForEach(recents, id: \.self) { item in
                        Button {
                            query = item
                        } label: {
                            Label(item, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    HStack {
                        Text("最近搜尋")
                        Spacer()
                        Button("清除") { recentStorage = "" }
                            .font(.footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func remember(_ keyword: String) {
        guard !keyword.isEmpty else { return }
        let list = [keyword] + recents.filter { $0 != keyword }
        recentStorage = list.prefix(10).joined(separator: "\n")
    }
}
