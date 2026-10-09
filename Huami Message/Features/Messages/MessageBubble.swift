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

    /// 群聊里这条是谁发的。一对一为 nil（一对一只需要分"我 / 他"）。
    ///
    /// 查不到时（缓存还没填上）是 nil —— 那就**不显示名字**，
    /// 而不是显示一个猜的名字。宁可不显示，也不要显示错的。
    var sender: GroupMember? = nil

    /// 点了头像之后要看的那个人的资料
    @State private var openedProfile: GroupMember?

    /// 发送失败时，用户点"重试"会调它
    var onRetry: () -> Void = {}

    /// 长按菜单里点"删除"会调它
    var onDelete: () -> Void = {}

    private var isMine: Bool { message.sender == .me }

    var body: some View {
        // ── 对齐方式：头像**垂直居中** ──
        //
        // 试过两种，都不对：
        //   · 底部对齐 → 头像掉到气泡底下，和昵称隔着整个气泡
        //   · 顶部对齐 → 上面对齐了，但**下面空一大截**
        //     （昵称那一行把气泡推下去，头像却只有那么高）
        //
        // 微信确实是顶部对齐，但它的气泡普遍只有一两行 ——
        // 一长就同样会露出下面那一截空。用户要的是"上下都别空太多"，
        // 那答案就是居中：头像对着「昵称 + 气泡」这一整列的中线，
        // 两边留的空一样多，看起来才是"嵌进去"的。
        //
        // 时间仍然要贴底（和气泡底边齐平），所以它单独用
        // alignmentGuide 把对齐基准换掉。
        HStack(alignment: .center, spacing: 0) {
            if isMine { Spacer(minLength: 56) }

            // ── 头像：放在气泡**旁边**（微信那样），不是上面 ──
            //
            // 为什么必须点得动：群里七八个人说话时，
            // 光看头像认不出是谁，而"这个人是谁、能不能加他"是接着要问的问题。
            if !isMine, let sender {
                Button {
                    Haptics.tap()
                    openedProfile = sender
                } label: {
                    Avatar(initial: sender.initial,
                           seed: sender.avatarSeed,
                           // 用户说"可以适当放大"。
                           // 34 偏小，40 和输入栏那两个圆钮同尺寸，
                           // 整屏看下来比例更稳。
                           size: 40,
                           url: sender.avatarURL)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            // ── 时间贴在内侧 ──
            //
            // 我发的消息靠右，所以"内侧"是它的左边；
            // 对方发的靠左，内侧是它的右边。
            // 这样时间永远挨着对话中间，而不是贴着屏幕边缘。
            if isMine {
                metaRow
                    .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }   // 按底边对齐
                    .padding(.trailing, 6)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                // 群聊里"别人发的"要标出是谁 —— 三个人说话时，
                // 只知道"不是我"等于不知道。名字放在气泡正上方。
                if !isMine, let sender {
                    Text(sender.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }

                if let imageURL = message.imageURL {
                    // 图片消息。
                    //
                    // 图片**不加左右内边距** —— 文字需要留白才好读，
                    // 图片本身有内容，再加一圈白边会显得缩手缩脚。
                    // 只留 3 磅，让圆角裁切不至于切到画面。
                    ChatImageView(url: imageURL)
                        .padding(3)
                        .background { bubble }
                        .opacity(message.status == .sending ? 0.72 : 1)
                } else if let audioURL = message.audioURL {
                    // 语音消息：一个播放键 + 时长。
                    VoiceBubble(url: audioURL,
                                seconds: message.audioSeconds ?? 0,
                                isMine: isMine)
                        .background { bubble }
                        .opacity(message.status == .sending ? 0.72 : 1)
                } else {
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(isMine ? .white : Theme.textPrimary)
                        // 长按可以选中复制 —— 聊天 App 的基本功能，少一行都会被人抱怨
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background { bubble }
                        // 发送中和发送失败时压暗一点，让「还没成功」这件事一眼可见
                        .opacity(message.status == .sending ? 0.72 : 1)
                }

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

            if !isMine {
                metaRow
                    .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }   // 按底边对齐
                    .padding(.leading, 6)
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
    
        // 点群成员头像 → 看他是谁。
        // 挂在这里（body 的最外层），不是挂在气泡背景那个属性上 ——
        // 挂在后者上编译不过（那不是 View 上下文）。
        .sheet(item: $openedProfile) { member in
            MemberProfileSheet(member: member)
        }
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
                .foregroundStyle(Theme.textTertiary)

            if isMine { statusView }
        }
        .padding(.horizontal, 4)
        // 和气泡底边对齐时，往上抬一点点看着更稳
        //（文字基线比气泡底边低一点，不抬会显得往下掉）
        .padding(.bottom, 3)
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
                .tint(Theme.textSecondary)

        case .failed:
            // 失败必须是**可以点的**，而且要说清楚点它会干什么。
            Button(action: onRetry) {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("发送失败，重试")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.danger)
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
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        } else {
            // 好友发的：毛玻璃。背景的极光会从气泡里透出来，
            // 而且是「半透明地透」，比纯色块高级得多。
            RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 0.8)
                }
        }

    }
}
