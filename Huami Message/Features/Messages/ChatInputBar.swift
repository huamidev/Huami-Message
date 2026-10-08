import SwiftUI

/// 悬浮在底部的输入栏。
///
/// 【布局为什么是「加号 / 发送」二选一】
///
/// 空着的时候右边是「+」，有字的时候变成「发送」。
/// 这是微信、Telegram 那套做法，理由是：
///
///   · 输入框右边**只有一个位置**。摆两个按钮，每个都得缩小，
///     而这两个动作在时间上是**互斥的** —— 你没打字时不会想发送，
///     你在打字时也不会想去翻工具栏。
///   · 于是让它们轮流用那个位置，每个都能做得够大、够好点。
///
/// 【为什么把 ✨ 从输入栏拿掉了】
///
/// 它原来占着输入框左边第一格。但既然要做工具栏，
/// 「AI 改写」就该和「复制」「粘贴」待在一起 ——
/// 它们是同一类东西（对这句话做点什么），不该一个在左一个在右。
struct ChatInputBar: View {

    @Binding var text: String

    /// 工具栏是不是打开着（用来把「+」转成「×」）
    var toolsOpen: Bool
    var onToggleTools: () -> Void
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {

            TextField("说点什么…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...5)
                .focused($isFocused)

            // 那一个位置：要么是发送，要么是加号
            ZStack {
                if canSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.myBubbleGradient, in: Circle())
                    }
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("发送")
                } else {
                    Button(action: onToggleTools) {
                        Image(systemName: toolsOpen ? "xmark" : "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(Theme.surfaceAlt, in: Circle())
                            .overlay { Circle().strokeBorder(Theme.separator, lineWidth: 0.8) }
                            .rotationEffect(.degrees(toolsOpen ? 90 : 0))
                    }
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(toolsOpen ? "收起工具栏" : "打开工具栏")
                }
            }
            .animation(.snappy(duration: 0.2), value: canSend)
            .animation(.snappy(duration: 0.2), value: toolsOpen)
        }
        .padding(8)
        // 用 regular 而不是 ultraThin：打字要看清文字，玻璃得「厚」一点。
        // 毛玻璃的厚度是有功能考虑的，不只是审美。
        .card(.elevated, radius: 26)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
