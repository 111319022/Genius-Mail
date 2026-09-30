import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var email = UserDefaults.standard.string(forKey: "lastLoginEmail") ?? ""
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
                        Image(systemName: "at")
                            .foregroundStyle(.secondary)
                        TextField("電子郵件", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
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
                .disabled(email.isEmpty || password.isEmpty || isLoading)

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
        .onAppear { if email.isEmpty { focus = .email } }
    }

    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func login() async {
        guard !email.isEmpty, !password.isEmpty, !isLoading else { return }
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
