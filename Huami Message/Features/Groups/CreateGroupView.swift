import SwiftUI

/// 发起群聊：选人 → 起名 → 建。
///
/// 【为什么先选人、再起名】
///
/// 真实的使用顺序就是这样：脑子里先有"要和这几个人说件事"，
/// 群名往往是最后才想的（甚至建完才改）。
/// 反过来先让人填名字，会卡在"叫什么好呢"这一步 —— 而他真正想做的事
/// 是赶紧把那几个人拉进来。
///
/// 所以名字那一步放在后面，而且**预填一个默认名**，
/// 用户不想改可以直接建。
struct CreateGroupView: View {

    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// 建完之后把新群 id 交出去 —— 列表可以顺手滚到它
    var onCreated: (UUID) -> Void = { _ in }

    @State private var picked: Set<UUID> = []
    @State private var title = ""
    @State private var isWorking = false
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    /// 只能拉一对一的好友进来 —— 群不能嵌套群（这一版不做）
    private var candidates: [Conversation] {
        store.conversations
            .filter { $0.friend.kind == .direct }
            .sorted { $0.friend.displayName < $1.friend.displayName }
    }

    private var canCreate: Bool {
        !picked.isEmpty && !isWorking
    }

    /// 没填名字就用「我、他、他」当默认名 —— 微信也是这样，
    /// 而且这样做的好处是：**用户永远不需要面对一个空的必填项**。
    private var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let names = candidates
            .filter { picked.contains($0.friend.id) }
            .map { $0.friend.displayName }
        let me = "我"
        let shown = ([me] + names).prefix(4).joined(separator: "、")
        return names.count + 1 > 4 ? shown + "…" : shown
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("发起群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("创建") { create() }
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
            .safeAreaInset(edge: .bottom) { nameBar }
        }
    }

    // MARK: - 选人

    private var list: some View {
        List {
            Section {
                ForEach(candidates) { convo in
                    row(convo)
                }
            } header: {
                Text(picked.isEmpty ? "选要拉进来的人" : "已选 \(picked.count) 人")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ convo: Conversation) -> some View {
        Button {
            Haptics.selection()
            if picked.contains(convo.friend.id) {
                picked.remove(convo.friend.id)
            } else {
                picked.insert(convo.friend.id)
            }
        } label: {
            HStack(spacing: 12) {
                // 选中状态用**勾**表示，而不是只靠背景色 ——
                // 色弱用户也能一眼看出来
                Image(systemName: picked.contains(convo.friend.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(picked.contains(convo.friend.id)
                                     ? Theme.accent : Theme.textTertiary.opacity(0.5))

                Avatar(initial: convo.friend.initial,
                       seed: convo.friend.avatarSeed,
                       size: 38,
                       url: convo.friend.avatarURL)

                Text(convo.friend.displayName)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 群名

    private var nameBar: some View {
        VStack(spacing: 8) {
            if let problem {
                Text(problem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                TextField(effectiveTitle, text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { if canCreate { create() } }
                    .padding(.horizontal, 14)
                    .frame(height: ChatInputBar.controlHeight)

                if isWorking {
                    ProgressView().controlSize(.small).frame(width: 30)
                }
            }
            .padding(7)
            .pillGlassBackground()
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .background(Theme.background)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text("还没有好友")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("先加一个好友，才能建群。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 建

    private func create() {
        guard canCreate else { return }
        nameFocused = false
        isWorking = true
        problem = nil

        // ⚠️ **必须用用户名，不能用昵称。**
        //    服务器按 profiles.username 找人，拿昵称去查会报
        //    "找不到用户名：huami888"（那是昵称）。
        let usernames = candidates
            .filter { picked.contains($0.friend.id) }
            .map { $0.friend.username }
            .filter { !$0.isEmpty }
        guard usernames.count == picked.count else {
            problem = "有人的用户名还没同步下来，下拉刷新一次再试。"
            isWorking = false
            return
        }
        let finalTitle = effectiveTitle

        Task {
            do {
                // 建群查的是**用户名**，不是昵称 —— 服务器那边按 profiles.username 找。
                // （这里传的是 friend.name，也就是对端资料里的 display_name…
                //  所以真正可靠的来源是 ChatStore 里那份 username 缓存，
                //  见下面 createGroup 的说明。）
                let id = try await store.createGroup(title: finalTitle,
                                                     usernames: usernames)
                Haptics.success()
                onCreated(id)
                dismiss()
            } catch {
                problem = (error as? LocalizedError)?.errorDescription
                    ?? "建群失败，等一下再试。"
                Haptics.warning()
            }
            isWorking = false
        }
    }
}
