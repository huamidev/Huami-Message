import SwiftUI

/// 悬浮在底部的输入栏。
///
/// 【布局照 Telegram】
///
///     (📎)  [ (头像) 说点什么…  ✨ ]  (🎤)
///
/// 左边一个圆形的回形针（附件），中间一个长胶囊，
/// 右边一个圆形的麦克风。右边那个**有字的时候会变成发送**。
///
/// 几个决定：
///
/// · **回形针而不是"+"**：加号太抽象，用户不知道点开是什么。
///   回形针是"附带点东西"的通用符号，一眼就懂。
///
/// · **头像放在输入框里面**：它不承担任何功能，只是一个"这是你在说话"的
///   视觉锚点。放在框里不占额外位置，也不抢注意力。
///
/// · **麦克风和发送共用一个位置**：和之前"加号/发送二选一"是同一个道理 ——
///   没打字时不会想发送，打字时也不会想录音。轮流用，每个都能做得够大。
struct ChatInputBar: View {

    @Environment(AuthStore.self) private var auth

    @Binding var text: String

    var toolsOpen: Bool
    var onToggleTools: () -> Void
    var onPolish: () -> Void
    var onVoice: () -> Void
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            circleButton(icon: toolsOpen ? "xmark" : "paperclip",
                         label: toolsOpen ? "收起工具栏" : "附件",
                         rotated: toolsOpen,
                         action: onToggleTools)

            inputPill

            // 一个位置，两个身份
            ZStack {
                if canSend {
                    circleButton(icon: "arrow.up",
                                 label: "发送",
                                 filled: true,
                                 action: onSend)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    circleButton(icon: "mic.fill",
                                 label: "语音",
                                 action: onVoice)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: canSend)
        }
        .padding(7)
        .card(.elevated, radius: 26)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - 中间的胶囊

    private var inputPill: some View {
        HStack(spacing: 8) {
            // 头像：纯粹是"这是你在说话"的锚点
            if let account = auth.account {
                Avatar(initial: String(account.displayName.prefix(1)).uppercased(),
                       seed: account.avatarSeed,
                       size: 26)
            }

            TextField("说点什么…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...5)
                .focused($isFocused)

            // Telegram 这个位置是表情。我们放 AI 改写 ——
            // 同一个视觉位置，但按下去真的有事发生
            //（放一个点了没反应的表情按钮，比空着还糟）。
            if canSend {
                Button(action: onPolish) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI 改写这句话")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: canSend)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.surfaceAlt, in: Capsule())
    }

    // MARK: - 圆形按钮

    private func circleButton(icon: String,
                              label: String,
                              filled: Bool = false,
                              rotated: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? .white : Theme.textSecondary)
                .frame(width: 34, height: 34)
                .background {
                    if filled {
                        Circle().fill(Theme.myBubbleGradient)
                    } else {
                        Circle().fill(Theme.surfaceAlt)
                            .overlay { Circle().strokeBorder(Theme.separator, lineWidth: 0.8) }
                    }
                }
                .rotationEffect(.degrees(rotated ? 90 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
