import SwiftUI
import UIKit   // 复制到剪贴板要用 UIPasteboard

/// 一条消息的气泡。
///
/// 四个设计决定值得说明：
///
/// 1. **我发的和好友发的，用的是两种完全不同的材质。**
///    我发的是实心渐变（有分量、有存在感），好友发的是毛玻璃（轻、背后透光）。
///    一实一虚，对话的层次一眼就出来了，不需要额外加边框或分隔线。
///    这是 Apple Music 那种「层次感」在聊天场景里的用法。
///
/// 2. **气泡是「弹」出来的，不是淡入的。**
///    scale 从 0.88 放大到 1，锚点在气泡的底角（就像从输入框里长出来）。
///    淡入显得平，弹出来才有生命力 —— 这是「丝滑」里最便宜也最有效的一招。
///
/// 3. **发送状态必须看得见。**
///    发送中转圈、失败变红并且能点重试。
///    用户永远不该猜"这条到底发出去没有"。
///
/// 4. **长按要有菜单。**
///    复制和删除是最基本的两个动作。少了它们，用户会觉得"这 App 不让我管自己的东西"。
struct MessageBubble: View {

    let message: Message

    /// 发送失败时，用户点"重试"会调它
    var onRetry: () -> Void = {}

    /// 长按菜单里点"删除"会调它
    var onDelete: () -> Void = {}

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
                    // 发送中和发送失败时压暗一点，让「还没成功」这件事一眼可见
                    .opacity(message.status == .sending ? 0.72 : 1)

                metaRow
            }
            // 长按气泡 → 弹出操作菜单
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
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

    // MARK: - 气泡下面那一行小字

    private var metaRow: some View {
        HStack(spacing: 6) {
            if let style = message.polishedWith {
                // 让用户清楚地知道"这条是 AI 改过的"，而不是偷偷改了发出去
                Label(style.title, systemImage: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(style.tint)
            }

            Text(message.sentAt, format: .dateTime.hour().minute())
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))

            if isMine { statusView }
        }
        .padding(.horizontal, 4)
    }

    /// 我发的消息才需要状态。好友发来的消息永远是"已送达"，不用显示。
    @ViewBuilder
    private var statusView: some View {
        switch message.status {
        case .sending:
            // 转圈本身不需要文字。它存在的意义是"告诉你还在努力"，
            // 而不是让你盯着它数秒数。
            ProgressView()
                .controlSize(.mini)
                .tint(.white.opacity(0.55))

        case .failed:
            // 失败必须是**可以点的**，而且要说清楚点它会干什么。
            Button(action: onRetry) {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("发送失败，重试")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
            }
            .buttonStyle(.plain)

        case .sent:
            // 成功不显示任何东西。
            // 这是有意的：聊天记录里满屏的对勾是噪音，
            // 只有"没成功"才值得占用你的注意力。
            EmptyView()
        }
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
