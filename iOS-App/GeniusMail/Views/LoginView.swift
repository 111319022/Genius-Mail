import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var username = Self.savedUsername
    @State private var domain = Self.defaultDomain(for: APIClient.shared.serverURL)
    @State private var password = ""
    @State private var server = APIClient.shared.serverURL
    @State private var showServer = false
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, server }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(.logo)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .shadow(color: .yellow.opacity(0.35), radius: 20, y: 8)
                    Text("Genius Mail")
                        .font(.largeTitle.bold())
                    Text("登入你的信箱")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(spacing: 12) {
                    field {
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                        TextField("帳號", text: $username)
                            .textContentType(.username)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                        // 只输入 @ 前面的部分；若自己打了完整地址就不显示后缀
                        if !username.contains("@") && !domain.isEmpty {
                            Text("@\(domain)")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    field {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                        SecureField("密碼", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await login() } }
                    }

                    if showServer {
                        field {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.secondary)
                            TextField("伺服器網址", text: $server)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .server)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await login() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("登入").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(username.isEmpty || password.isEmpty || isLoading)

                Button(showServer ? "隱藏伺服器設定" : "伺服器設定") {
                    withAnimation(.snappy) { showServer.toggle() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(colors: [Color.yellow.opacity(0.18), Color(.systemBackground)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .onAppear { if username.isEmpty { focus = .email } }
        .task(id: server) { await loadDomain() }
    }

    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private var email: String {
        let name = username.trimmingCharacters(in: .whitespaces)
        return name.contains("@") || domain.isEmpty ? name : "\(name)@\(domain)"
    }

    private static var savedUsername: String {
        let saved = UserDefaults.standard.string(forKey: "lastLoginEmail") ?? ""
        let domain = defaultDomain(for: APIClient.shared.serverURL)
        if !domain.isEmpty, saved.lowercased().hasSuffix("@" + domain.lowercased()) {
            return String(saved.dropLast(domain.count + 1))
        }
        return saved
    }

    /// 预设使用伺服器网域（mail.rayisgenius.cc），载入网站设定后改用第一个信箱网域
    private static func defaultDomain(for server: String) -> String {
        var value = server.trimmingCharacters(in: .whitespaces)
        if !value.hasPrefix("http") { value = "https://" + value }
        return URL(string: value)?.host() ?? ""
    }

    private func loadDomain() async {
        try? await Task.sleep(for: .milliseconds(300))
        let target = server.isEmpty ? APIClient.defaultServer : server
        domain = Self.defaultDomain(for: target)

        // 登录前还没有 token，直接向该伺服器查询公开的网站设定
        var base = target.trimmingCharacters(in: .whitespaces)
        if !base.hasPrefix("http") { base = "https://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/api/setting/websiteConfig"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = json["data"] as? [String: Any],
              let first = (config["domainList"] as? [String])?.first else { return }
        domain = first.hasPrefix("@") ? String(first.dropFirst()) : first
    }

    private func login() async {
        guard !username.isEmpty, !password.isEmpty, !isLoading else { return }
        focus = nil
        isLoading = true
        error = nil
        defer { isLoading = false }

        APIClient.shared.serverURL = server.isEmpty ? APIClient.defaultServer : server
        do {
            try await session.login(email: email, password: password)
            UserDefaults.standard.set(email, forKey: "lastLoginEmail")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    LoginView().environment(Session())
}
