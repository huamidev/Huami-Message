import SwiftUI

/// 悬浮在底部的输入栏。
///
/// 三件事让它是「丝滑」的而不是「卡顿」的：
///
/// 1. 用 `TextField(axis: .vertical)` 让它自动长高（1 到 5 行）。
///    以前要自己算高度、监听文字行数，现在系统全包了。
///
/// 2. 整个输入栏是一块**悬浮的毛玻璃**，压在消息流上面。
///    消息从它底下滚过去时，你会看到模糊的颜色在动 ——
///    这是毛玻璃最出彩的地方，也是为什么它适合用在输入框上。
///
/// 3. 发送按钮在没打字时是缩小的、透明的，有字时「啵」地弹出来并亮起。
///    这个即时反馈很重要：用户不用确认就知道「现在可以发了」。
struct ChatInputBar: View {

    @Binding var text: String
    var onPolish: () -> Void
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {

            // ── AI 润色的入口 ──
            // 放在输入框**左边第一格**，而不是塞进「更多」菜单。
            // 原因：这是这个产品的核心动作，必须一步可达。
            // 一个功能藏两层菜单，用户一辈子都不会发现它。
            Button(action: onPolish) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                    }
            }
            .disabled(!canSend)          // 没打字时没什么可润色的
            .opacity(canSend ? 1 : 0.35)
            .accessibilityLabel("AI 润色这句话")

            TextField("说点什么…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.myBubbleGradient, in: Circle())
            }
            .disabled(!canSend)
            .scaleEffect(canSend ? 1 : 0.7)
            .opacity(canSend ? 1 : 0)
            .animation(.snappy(duration: 0.22), value: canSend)
            .accessibilityLabel("发送")
        }
        .padding(8)
        // 这里用 regular 而不是 ultraThin：
        // 打字是需要看清文字的场景，玻璃要「厚」一点，保证可读性。
        // 毛玻璃的厚度选择是有功能考虑的，不只是审美。
        .glassCard(.regular, radius: 26)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
