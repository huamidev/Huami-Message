import SwiftUI

/// 搜索页。
///
/// 【为什么给它一个独立的底栏位置，而不是放在消息页顶上】
///
/// 用户要的是"像 Telegram 那样把搜索隔出来"。这件事的价值不只是好看：
///
///   · 放在消息页顶上时，搜索框会**一直占着一条**，
///     而它大部分时候是空着的 —— 占地方、又抢注意力
///   · 单独一页之后，进来就是**全屏的结果列表**，
///     不用在"聊天列表"和"结果"之间来回切
///
/// 它搜的是**本地数据**（好友名 + 消息内容），所以是边打字边出结果，
/// 不需要等网络。
struct SearchView: View {

    @Environment(ChatStore.self) private var store

    // 开发自检时用启动参数预填（截图没法打字）
    @State private var keyword = DevFlags.searchFor
    @State private var path: [Conversation] = []
    @FocusState private var focused: Bool

    private var hits: [SearchHit] { store.search(keyword) }

    var body: some View {
        NavigationStack(path: $path) {
            AppPage {
                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 10)

                    content
                }
            }
            .navigationTitle("搜索")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
            }
        }
    }

    // MARK: - 搜索框

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)

            TextField("搜好友或聊天记录", text: $keyword)
                .font(.system(size: 15))
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled(false)

            if !keyword.isEmpty {
                Button {
                    Haptics.tap()
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 三种状态

    @ViewBuilder
    private var content: some View {
        if keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            hint
        } else if hits.isEmpty {
            noResult
        } else {
            resultList
        }
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text("搜好友的名字，或者聊天里说过的话")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 120)
    }

    private var noResult: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text("没有找到「\(keyword)」")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, 120)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(hits) { hit in
                    Button {
                        open(hit)
                    } label: {
                        row(hit)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ hit: SearchHit) -> some View {
        HStack(spacing: 11) {
            switch hit.kind {
            case .friend:
                Avatar(initial: hit.friend.initial, seed: hit.friend.avatarSeed,
                       size: 40, url: hit.friend.avatarURL)
            case .message:
                // 消息命中用小一号的头像 + 一个气泡角标，
                // 让人一眼分清"这是一句话"而不是"这是个人"
                Avatar(initial: hit.friend.initial, seed: hit.friend.avatarSeed,
                       size: 34, url: hit.friend.avatarURL)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.friend.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    if hit.kind == .message {
                        Text("聊天记录")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.surfaceAlt, in: Capsule())
                    }

                    Spacer(minLength: 0)

                    if let date = hit.date {
                        Text(date, format: .dateTime.month().day())
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Text(hit.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.surface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 动作

    private func open(_ hit: SearchHit) {
        Haptics.tap()
        focused = false
        if let conversation = store.conversation(for: hit.friend.id) {
            path = [conversation]
        }
    }
}
