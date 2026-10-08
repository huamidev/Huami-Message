import SwiftUI

/// 「消息」页：会话列表。
///
/// 视觉上刻意做成「一张张浮起来的毛玻璃卡片」，而不是系统默认的
/// 一条条贴着边的白线列表 —— 后者是微信的样子，也是所有普通 App 的样子。
/// 卡片之间有间距，背景的极光从缝隙里透出来，一眼就有层次。
struct ConversationListView: View {

    @Environment(ChatStore.self) private var store

    /// 导航栈。
    /// 用「代码显式管理的栈」而不是让 NavigationLink 自己管，有两个好处：
    /// ① 代码可以主动压栈/出栈 —— 以后点推送通知直接跳到某个会话，靠的就是它；
    /// ② 调试时可以用启动参数直接进会话，省得手点。
    @State private var path: [Conversation] = []

    var body: some View {
        NavigationStack(path: $path) {
            GlassPage {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.conversations) { conversation in
                            NavigationLink(value: conversation) {
                                ConversationRow(conversation: conversation)
                            }
                            // 去掉系统默认的蓝色高亮和点击变灰，保持我们自己的外观
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 72)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("消息")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
            }
            .overlay {
                if store.isLoading && store.conversations.isEmpty {
                    ProgressView().tint(Theme.accent)
                }
            }
        }
        // 开发用：带 -openChat 1 启动时自动进第一个会话。
        // 这里加了 id:，是为了等会话列表加载完之后再执行一次。
        .task(id: store.conversations.count) {
            guard DevFlags.openChat, path.isEmpty,
                  let first = store.conversations.first else { return }
            path = [first]
        }
    }
}

// MARK: - 会话列表里的一行

private struct ConversationRow: View {

    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Avatar(
                initial: conversation.friend.initial,
                seed: conversation.friend.avatarSeed,
                size: 52
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.friend.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(timeLabel(conversation.lastTime))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                HStack(alignment: .center) {
                    Text(conversation.lastMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .glassCard(.thin)
    }

    /// 右上角的时间：今天的显示「时:分」，更早的显示「月/日」。
    /// 这是聊天 App 的通用习惯 —— 用户扫一眼就知道是新的还是旧的。
    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d"
        return formatter.string(from: date)
    }
}
