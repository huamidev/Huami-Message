import SwiftUI

/// 「消息」页：会话列表。
///
/// 视觉上刻意做成「一张张浮起来的毛玻璃卡片」，而不是系统默认的
/// 一条条贴着边的白线列表 —— 后者是微信的样子，也是所有普通 App 的样子。
/// 卡片之间有间距，背景的极光从缝隙里透出来，一眼就有层次。
///
/// 【这里为什么用 List 而不是 ScrollView】
/// 因为要支持**左滑操作**（删除会话、标记未读）。
/// SwiftUI 的 `.swipeActions` 只在 List 里生效，自己用 ScrollView 手写
/// 一套滑动手势既费劲又难以做得跟系统一样跟手。
///
/// 代价是 List 自带的白底和分隔线会破坏毛玻璃效果，所以要用三行代码把它关掉：
///   · .scrollContentBackground(.hidden)  关掉列表自己的背景
///   · .listRowBackground(Color.clear)     关掉每一行的背景
///   · .listRowSeparator(.hidden)          关掉行之间的分隔线
/// 关掉之后，List 就变成了一个"支持左滑的透明容器"，底下的极光照常透出来。
struct ConversationListView: View {

    @Environment(ChatStore.self) private var store

    /// 导航栈。
    /// 用「代码显式管理的栈」而不是让 NavigationLink 自己管，有两个好处：
    /// ① 代码可以主动压栈/出栈 —— 以后点推送通知直接跳到某个会话，靠的就是它；
    /// ② 调试时可以用启动参数直接进会话，省得手点。
    @State private var path: [Conversation] = []

    var body: some View {
        NavigationStack(path: $path) {
            AppPage {
                List {
                    ForEach(store.conversations) { conversation in
                        // 用 Button 手动压栈，而不用 NavigationLink ——
                        // 因为 List 里的 NavigationLink 会自动加一个灰色小箭头，
                        // 那会破坏我们自己的卡片外观。
                        Button {
                            path.append(conversation)
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                            // 删除会话 —— 连同聊天记录一起删掉。
                            // 这是审核要求的"用户必须能删掉自己的数据"。
                            Button(role: .destructive) {
                                withAnimation(.snappy) {
                                    store.deleteConversation(conversation.friend.id)
                                }
                            } label: {
                                Label("删除", systemImage: "trash.fill")
                            }

                            // 标记未读：把这条会话标成"待会儿要回"。
                            // 聊天 App 里这是个高频小动作，能省掉很多"忘了回"。
                            Button {
                                withAnimation(.snappy) {
                                    store.setUnread(conversation.unreadCount > 0 ? 0 : 1,
                                                    for: conversation.friend.id)
                                }
                            } label: {
                                Label(conversation.unreadCount > 0 ? "已读" : "未读",
                                      systemImage: conversation.unreadCount > 0
                                          ? "envelope.open.fill" : "envelope.badge.fill")
                            }
                            .tint(Theme.accent)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 96, for: .scrollContent)
            }
            .navigationTitle("消息")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
            }
            .overlay {
                if store.isLoading && store.conversations.isEmpty {
                    ProgressView().tint(Theme.accent)
                }
                // 一个会话都没有的时候，给一句话，别让人对着空白猜
                if !store.isLoading && store.conversations.isEmpty {
                    emptyHint
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

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有聊天")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("第 1 步接上服务器后，就能加真实好友了")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
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
            // 拉黑的人，头像压暗 —— 一眼就能看出来这条会话是"被封住的"
            .opacity(conversation.isBlocked ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.friend.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if conversation.isBlocked {
                        Label("已拉黑", systemImage: "hand.raised.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer()

                    Text(timeLabel(conversation.lastTime))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack(alignment: .center) {
                    Text(conversation.lastMessage.isEmpty ? "（没有消息）" : conversation.lastMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
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
        .card()
    }

    /// 右上角的时间：今天的显示「时:分」，更早的显示「月/日」。
    /// 这是聊天 App 的通用习惯 —— 用户扫一眼就知道是新的还是旧的。
    private func timeLabel(_ date: Date) -> String {
        // 从来没有消息的会话，lastTime 是一个"极早"的占位值，显示成横线就好
        guard date != .distantPast else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d"
        return formatter.string(from: date)
    }
}
