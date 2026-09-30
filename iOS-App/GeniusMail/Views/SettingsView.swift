import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(PushManager.self) private var push
    @Environment(\.openURL) private var openURL

    @State private var pushStatus: PushStatus?
    @State private var testResults: [PushTestResult]?
    @State private var isTesting = false
    @State private var testError: String?
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                mailboxSection
                notificationSection
                aboutSection

                Section {
                    Button("登出", role: .destructive) { confirmLogout = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("設定")
            .refreshable { await reload() }
            .task { await reload() }
            .confirmationDialog("確定要登出嗎？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("登出", role: .destructive) { Task { await session.logout() } }
            } message: {
                Text("登出後這台裝置將不再收到推播通知")
            }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(name: session.user?.name ?? "", email: session.user?.email ?? "", size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.user?.name.isEmpty == false ? session.user!.name : "Genius Mail")
                        .font(.title3.weight(.semibold))
                    Text(session.user?.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let role = session.user?.role?.name, !role.isEmpty {
                        Text(role)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                    }
                }
            }
            .padding(.vertical, 4)

            if let user = session.user {
                LabeledContent("寄信額度", value: user.sendQuotaText)
            }
        }
    }

    private var mailboxSection: some View {
        Section("信箱") {
            NavigationLink {
                AccountsView()
            } label: {
                LabeledContent {
                    Text("\(session.accounts.count)")
                } label: {
                    Label("管理信箱", systemImage: "tray.2")
                }
            }
            @Bindable var session = session
            Picker(selection: $session.selectedAccountId) {
                Text("所有信箱").tag(Int?.none)
                ForEach(session.accounts) { account in
                    Text(account.email).tag(Int?.some(account.accountId))
                }
            } label: {
                Label("目前顯示", systemImage: "eye")
            }
        }
    }

    private var notificationSection: some View {
        Section {
            LabeledContent {
                Text(authorizationText)
                    .foregroundStyle(push.authorization == .authorized ? .green : .secondary)
            } label: {
                Label("通知權限", systemImage: "bell.badge")
            }

            if push.authorization == .notDetermined {
                Button("開啟推播通知") {
                    Task { await push.requestAuthorization() }
                }
            } else if push.authorization == .denied {
                Button("前往系統設定開啟") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }

            if let pushStatus {
                LabeledContent("伺服器推播", value: pushStatus.configured ? "已設定" : "尚未設定 APNs 金鑰")
                LabeledContent("已註冊裝置", value: "\(pushStatus.devices.count) 台")
            }

            if let error = push.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await sendTest() }
            } label: {
                HStack {
                    Text("傳送測試通知")
                    if isTesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isTesting || push.authorization != .authorized)

            if let testResults {
                ForEach(testResults, id: \.self) { result in
                    Label {
                        VStack(alignment: .leading) {
                            Text(result.name?.isEmpty == false ? result.name! : "…\(result.tokenSuffix)")
                            Text(result.ok ? "成功（\(result.env)）" : "\(result.reason ?? "失敗")（\(result.env)）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.ok ? .green : .red)
                    }
                }
            }
            if let testError {
                Text(testError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("通知")
        } footer: {
            Text("收到新郵件時會推播寄件人、主旨與內文預覽；有驗證碼時可以直接在通知上複製。")
        }
    }

    private var aboutSection: some View {
        Section("關於") {
            LabeledContent("伺服器", value: APIClient.shared.baseURL?.host() ?? "")
            if let url = APIClient.shared.baseURL {
                Link(destination: url) {
                    Label("開啟網頁版", systemImage: "safari")
                }
            }
            LabeledContent("版本", value: appVersion)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var authorizationText: String {
        switch push.authorization {
        case .authorized: "已開啟"
        case .denied: "已關閉"
        case .provisional: "暫時允許"
        case .ephemeral: "暫時允許"
        default: "尚未設定"
        }
    }

    private func reload() async {
        await push.refreshAuthorization()
        if push.authorization == .authorized && push.deviceToken == nil {
            push.registerIfAuthorized()
        }
        pushStatus = try? await APIClient.shared.get("/push/status")
        try? await session.loadProfile()
    }

    private func sendTest() async {
        isTesting = true
        testError = nil
        defer { isTesting = false }
        await push.uploadToken()
        do {
            testResults = try await APIClient.shared.post("/push/test", body: [:])
            if testResults?.isEmpty == true {
                testError = "伺服器上沒有已註冊的裝置，請確認通知權限已開啟"
            }
            pushStatus = try? await APIClient.shared.get("/push/status")
        } catch {
            testError = error.localizedDescription
        }
    }
}

struct AccountsView: View {
    @Environment(Session.self) private var session

    @State private var renaming: Account?
    @State private var newName = ""
    @State private var showAdd = false
    @State private var errorMessage: String?
    @State private var deleting: Account?

    var body: some View {
        List {
            Section {
                ForEach(session.accounts) { account in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(account.email)
                            if account.accountId == session.primaryAccount?.accountId {
                                Text("主要")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: .capsule)
                            }
                        }
                        Text("寄件名稱：\(account.name.isEmpty ? "—" : account.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if account.accountId != session.primaryAccount?.accountId {
                            Button("刪除", systemImage: "trash", role: .destructive) { deleting = account }
                        }
                        Button("改名", systemImage: "pencil") {
                            newName = account.name
                            renaming = account
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button("修改寄件名稱", systemImage: "pencil") {
                            newName = account.name
                            renaming = account
                        }
                        Button("複製地址", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = account.email
                        }
                        if account.accountId != session.primaryAccount?.accountId {
                            Button("刪除", systemImage: "trash", role: .destructive) { deleting = account }
                        }
                    }
                }
            } footer: {
                Text("向左滑可以修改寄件名稱或刪除信箱。")
            }
        }
        .navigationTitle("管理信箱")
        .toolbar {
            if session.config?.canAddAccount ?? true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新增信箱", systemImage: "plus") { showAdd = true }
                }
            }
        }
        .refreshable { try? await session.reloadAccounts() }
        .sheet(isPresented: $showAdd) {
            AddAccountSheet()
                .presentationDetents([.medium])
        }
        .alert("修改寄件名稱", isPresented: .init(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名稱", text: $newName)
            Button("取消", role: .cancel) {}
            Button("儲存") {
                guard let account = renaming else { return }
                Task { await rename(account) }
            }
        }
        .confirmationDialog("刪除信箱？", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("刪除 \(deleting?.email ?? "")", role: .destructive) {
                guard let account = deleting else { return }
                Task { await delete(account) }
            }
        } message: {
            Text("此信箱的郵件也會一併刪除")
        }
        .alert("操作失敗", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func rename(_ account: Account) async {
        do {
            let _: Empty = try await APIClient.shared.put("/account/setName", body: ["accountId": account.accountId, "name": newName])
            try await session.reloadAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ account: Account) async {
        do {
            let _: Empty = try await APIClient.shared.delete("/account/delete", query: ["accountId": account.accountId])
            try await session.reloadAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddAccountSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var prefix = ""
    @State private var domain = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var domains: [String] {
        let list = (session.config?.domainList ?? []).map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
        if list.isEmpty, let own = session.user?.email.split(separator: "@").last { return [String(own)] }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 4) {
                        TextField("名稱", text: $prefix)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        if domains.count > 1 {
                            Picker("", selection: $domain) {
                                ForEach(domains, id: \.self) { Text("@\($0)").tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        } else {
                            Text("@\(domain)").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    if session.config?.addAccountNeedsCaptcha == true {
                        Text("伺服器目前要求人機驗證才能新增信箱，App 內無法完成驗證；若新增失敗，請改用網頁版新增。")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .navigationTitle("新增信箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增", systemImage: "checkmark", role: .confirm) { Task { await save() } }
                        .disabled(prefix.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { if domain.isEmpty { domain = domains.first ?? "" } }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let email = "\(prefix.trimmingCharacters(in: .whitespaces))@\(domain)"
        do {
            let _: Account = try await APIClient.shared.post("/account/add", body: ["email": email])
            try await session.reloadAccounts()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
