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
    @Environment(AuthStore.self) private var auth

    /// 是否正在显示「加好友」
    @State private var showAddFriend = false

    /// 导航栈。
    /// 用「代码显式管理的栈」而不是让 NavigationLink 自己管，有两个好处：
    /// ① 代码可以主动压栈/出栈 —— 以后点推送通知直接跳到某个会话，靠的就是它；
    /// ② 调试时可以用启动参数直接进会话，省得手点。
    @State private var path: [Conversation] = []

    var body: some View {
        NavigationStack(path: $path) {
            AppPage {
                List {
                    // 演示数据标识。
                    // 朋友装上去第一眼看到"林一/妈妈/老周"会以为是真好友，
                    // 甚至怀疑自己的账号被盗了 —— 说清楚比让人猜好。
                    if store.isDemoData {
                        demoBanner
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }

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

                            // **删除聊天**（不是删除好友）。
                            //
                            // 只清掉我本地的记录，好友关系还在 —— 所以左滑之后
                            // 他还留在联系人里，还能继续聊。
                            //
                            // 这两个动作必须分清楚，所以文案写全：
                            // 左滑是「删除聊天」，删好友在聊天页右上角的菜单里。
                            //
                            // 另外一个硬要求：这是审核要的"用户必须能删掉自己的数据"。
                            Button(role: .destructive) {
                                withAnimation(.snappy) {
                                    store.deleteConversation(conversation.friend.id)
                                }
                            } label: {
                                Label("删除聊天", systemImage: "trash.fill")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            // ⚠️ 环境要在这里**再注入一次**。
            // 外层挂在 TabView 上的 .environment(...) 传不到弹窗内容里 ——
            // 这个坑我在做登录页时踩过一次，崩溃栈顶是
            // EnvironmentValues.subscript.getter。
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
                    .environment(store)
                    .environment(auth)
            }
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
        // 开发自检：自动打开「加好友」。
        //
        // ⚠️ 这里**必须延迟**，不能立刻打开。
        // 因为启动时登录用的 fullScreenCover 还盖在最上面 ——
        // 在那个覆盖还在的时候请求弹窗，会被**无声地吞掉**：
        // 不报错、不警告，就是什么都不发生。
        //
        // 这个坑在做登录页时也遇到过一次（那次是环境没传进去直接崩）。
        // 凡是"弹窗 / 全屏覆盖"，都要留意它们之间的时序。
        .task {
            guard DevFlags.openAddFriend else { return }
            try? await Task.sleep(for: .seconds(2))
            showAddFriend = true
        }
        .task(id: store.conversations.count) {

            guard path.isEmpty else { return }

            // 按名字打开（更精确）
            if !DevFlags.openChatName.isEmpty {
                if let target = store.conversations.first(where: {
                    $0.friend.name == DevFlags.openChatName
                }) {
                    path = [target]
                }
                return
            }

            guard DevFlags.openChat, let first = store.conversations.first else { return }
            path = [first]
        }
    }

    /// 「演示数据」横幅
    private var demoBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "testtube.2")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("演示数据")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("这些好友和消息都是假的，用来预览界面。接上服务器后会出现真实好友。")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.warning.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)

            Text("还没有聊天")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text(store.isDemoData
                 ? "上面的好友是演示数据，可以直接点进去看看界面。"
                 : "用用户名加一个好友就开始聊了。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)

            // 空状态里必须给一个**能点的出口**。
            // 只说"还没有聊天"等于把用户扔在原地 —— 他知道该干什么，但得自己去找。
            if !store.isDemoData {
                Button {
                    Haptics.tap()
                    showAddFriend = true
                } label: {
                    Text("加好友")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Theme.myBubbleGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 40)
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
                size: 52,
                url: conversation.friend.avatarURL
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
