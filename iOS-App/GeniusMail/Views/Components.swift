import SwiftUI
import UIKit

/// 依名称产生固定颜色的圆形头像
struct AvatarView: View {
    let name: String
    let email: String
    var size: CGFloat = 40

    private static let palette: [Color] = [.orange, .pink, .purple, .indigo, .blue, .teal, .green, .mint, .brown, .red, .cyan]

    private var initial: String {
        let source = name.isEmpty ? email : name
        return source.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    private var color: Color {
        let key = (email.isEmpty ? name : email).lowercased()
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// 验证码胶囊，点一下复制
struct CodeChip: View {
    let code: String
    var large = false
    @Environment(PushManager.self) private var push

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            push.showToast("已複製驗證碼 \(code)")
        } label: {
            HStack(spacing: large ? 10 : 5) {
                Image(systemName: "key.fill")
                    .font(large ? .body : .caption2)
                Text(code)
                    .font(large ? .title2.monospacedDigit().weight(.semibold) : .caption.monospacedDigit().weight(.semibold))
                    .kerning(large ? 2 : 0.5)
                if large {
                    Spacer()
                    Label("複製", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, large ? 16 : 8)
            .padding(.vertical, large ? 14 : 4)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: large ? 14 : 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("驗證碼 \(code)，點兩下複製")
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 简单的换行排版，用于收件人胶囊
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 信箱切换选单（导航列左上角）
struct AccountMenu: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var session = session
        Menu {
            Picker("信箱", selection: $session.selectedAccountId) {
                Label("所有信箱", systemImage: "tray.2").tag(Int?.none)
                ForEach(session.accounts) { account in
                    Text(account.email).tag(Int?.some(account.accountId))
                }
            }
        } label: {
            Image(systemName: session.selectedAccountId == nil ? "tray.2" : "person.crop.circle")
        }
        .accessibilityLabel("切換信箱，目前為 \(session.scopeTitle)")
    }
}

extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    var isValidEmail: Bool {
        range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}
