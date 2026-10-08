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
    @State private var copied = false

    /// 按名字排 —— 找人时人是按字母/拼音顺序回忆的，不是按聊天时间
    private var sorted: [Conversation] {
        store.conversations.sorted { $0.friend.name < $1.friend.name }
    }

    var body: some View {
        NavigationStack(path: $path) {
            AppPage {
                ScrollView {
                    VStack(spacing: 14) {
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
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
                    .environment(store)
                    .environment(auth)
            }
        }
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
                               size: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.friend.name)
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
