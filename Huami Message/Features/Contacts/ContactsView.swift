import SwiftUI

/// 联系人页。
///
/// 【它和消息页有什么区别】
///
/// 消息页是"最近聊过的人"（按时间排，有未读标记）；
/// 这里是"我所有的好友"（按名字排，稳定的顺序）。
///
/// 好友少的时候两者看起来差不多，但**加好友的入口放在这里更合理** ——
/// 它是"维护关系"的动作，不是"看消息"的动作。
struct ContactsView: View {

    @Environment(ChatStore.self) private var store
    @Environment(AuthStore.self) private var auth

    @State private var path: [Conversation] = []
    @State private var showAddFriend = false
    @State private var showRequests = false
    @State private var showCreateGroup = false
    @State private var copied = false

    /// 按名字排 —— 找人时人是按字母/拼音顺序回忆的，不是按聊天时间
    private var sorted: [Conversation] {
        // ⚠️ **通讯录只列一对一。**
        //
        // 群聊在本地模型里也是一段"会话"（共用 StoredFriend 那一行），
        // 所以不加这个过滤，群会跑到通讯录里冒充好友 ——
        // 用户的原话是"群聊变成了通讯录的好友"。
        //
        // 群不是联系人。它属于消息列表，不属于通讯录。
        store.conversations
            .filter { $0.friend.kind == .direct }
            .sorted { $0.friend.displayName < $1.friend.displayName }
    }

    var body: some View {
        NavigationStack(path: $path) {
            AppPage {
                ScrollView {
                    VStack(spacing: 14) {
                        newFriendsCard
                        createGroupCard
                        myCodeCard
                        if sorted.isEmpty { emptyHint } else { friendList }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("联系人")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
            }
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
            // 环境要显式传进弹窗 —— 这个坑踩过两次了
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView()
                    .environment(store)
            }
            .sheet(isPresented: $showRequests) {
                FriendRequestsView()
                    .environment(store)
                    .environment(auth)
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
                    .environment(store)
                    .environment(auth)
            }
        }
    }

    // MARK: - 新的朋友

    /// 待处理的申请入口。
    ///
    /// 单独摆在最上面，带一个数字 —— 因为它是**待办**，不是联系人。
    /// 没有待办时它也在，但安安静静的（没有数字）。
    /// 发起群聊。
    ///
    /// 放在联系人页，而不是消息页右上角那个加号里 ——
    /// 建群的**原料是好友**，而这一页就是好友所在的地方。
    /// 从"选人"的语境里点"建群"，比从"消息列表"里点更顺。
    private var createGroupCard: some View {
        Button {
            Haptics.tap()
            showCreateGroup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text("发起群聊")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newFriendsCard: some View {
        Button {
            Haptics.tap()
            showRequests = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text("新的朋友")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                if !store.incomingRequests.isEmpty {
                    Text("\(store.incomingRequests.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.danger, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 我的用户名

    private var myCodeCard: some View {
        Button {
            Haptics.tap()
            showAddFriend = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("加好友")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("用用户名加我，或者让对方扫你的码")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 0)

                if let username = auth.account?.username, !username.isEmpty {
                    Text("@" + username)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accentSoft, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 好友列表

    private var friendList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(sorted.count) 位好友")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 4)

            ForEach(sorted) { conversation in
                Button {
                    Haptics.tap()
                    path = [conversation]
                } label: {
                    HStack(spacing: 12) {
                        Avatar(initial: conversation.friend.initial,
                               seed: conversation.friend.avatarSeed,
                               size: 44,
                               url: conversation.friend.avatarURL)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.friend.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(conversation.lastMessage.isEmpty
                                 ? "还没有聊过"
                                 : conversation.lastMessage)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if conversation.isBlocked {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 9) {
            Image(systemName: "person.2")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有好友")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("点上面的「加好友」，把你的用户名给对方，或者让对方把用户名给你。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .padding(.top, 50)
    }
}
