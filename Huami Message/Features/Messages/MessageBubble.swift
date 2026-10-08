import SwiftUI

/// 一条消息的气泡。
///
/// 两个设计决定值得说明：
///
/// 1. **我发的和好友发的，用的是两种完全不同的材质。**
///    我发的是实心渐变（有分量、有存在感），好友发的是毛玻璃（轻、背后透光）。
///    一实一虚，对话的层次一眼就出来了，不需要额外加边框或分隔线。
///    这是 Apple Music 那种「层次感」在聊天场景里的用法。
///
/// 2. **气泡是「弹」出来的，不是淡入的。**
///    scale 从 0.88 放大到 1，锚点在气泡的底角（就像从输入框里长出来）。
///    淡入显得平，弹出来才有生命力 —— 这是「丝滑」里最便宜也最有效的一招。
struct MessageBubble: View {

    let message: Message

    private var isMine: Bool { message.sender == .me }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isMine { Spacer(minLength: 56) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(isMine ? .white : Color.white.opacity(0.92))
                    // 长按可以选中复制 —— 聊天 App 的基本功能，少一行都会被人抱怨
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background { bubble }

                // 气泡下面一行小字：时间 + 「这条是 AI 改过的」标记
                HStack(spacing: 6) {
                    if let style = message.polishedWith {
                        Label(style.title, systemImage: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(style.tint)
                    }
                    Text(message.sentAt, format: .dateTime.hour().minute())
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 56) }
        }
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.88, anchor: isMine ? .bottomTrailing : .bottomLeading)
                    .combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    @ViewBuilder
    private var bubble: some View {
        if isMine {
            // 我发的：主色渐变 + 一层同色柔光，让气泡「浮」在背景上
            RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                .fill(Theme.myBubbleGradient)
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 4)
        } else {
            // 好友发的：毛玻璃。背景的极光会从气泡里透出来，
            // 而且是「半透明地透」，比纯色块高级得多。
            RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                .fill(GlassThickness.thin.material)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                }
        }
    }
}
