import SwiftUI

/// 群资料页：群名、成员、拉人、退群。
///
/// 【为什么这一页值得单独做】
///
/// 群里最常被问的三个问题是"这都谁啊""这群叫啥""我怎么退"。
/// 前两个别人问，第三个自己问 —— 而**退群必须能自己做到**，
/// 不然进了不想进的群就只能一直待着。
struct GroupInfoView: View {

    let conversation: Conversation

    /// 退群成功后告诉外面 —— 聊天页要跟着关掉，
    /// 不然用户还停在"一个自己已经不在的群"里发消息。
    var onLeft: () -> Void = {}

    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var members: [GroupMember] = []
    @State private var title = ""
    @State private var isWorking = false
    @State private var problem: String?
    @State private var showAddMembers = false
    @State private var showLeaveConfirm = false

    private var me: GroupMember? {
        guard let myID = store.myID else { return nil }
        return members.first { $0.id == myID }
    }

    /// 群主才能改名字。成员列表还没拉回来时先不当群主 ——
    /// 宁可晚一秒出现按钮，也不要让非群主看到一个点了会被拒的入口。
    private var iAmOwner: Bool { me?.isOwner ?? false }

    /// 可以拉进来的人：好友里还不在这个群里的
    private var invitable: [Conversation] {
        let inGroup = Set(members.map(\.id))
        return store.conversations
            .filter { $0.friend.kind == .direct && !inGroup.contains($0.friend.id) }
            .sorted { $0.friend.displayName < $1.friend.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                header
                membersSection
                actionsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("群聊信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await reload()
            }
            .sheet(isPresented: $showAddMembers) {
                AddMembersSheet(candidates: invitable) { picked in
                    await addMembers(picked)
                }
                .environment(store)
            }
            .confirmationDialog("退出这个群？",
                                isPresented: $showLeaveConfirm,
                                titleVisibility: .visible) {
                Button("退出群聊", role: .destructive) {
                    Task { await leave() }
                }
                Button("再想想", role: .cancel) {}
            } message: {
                Text("退出之后就收不到这个群的消息了。想回来得让别人重新拉你。")
            }
            .alert("没能完成", isPresented: .constant(problem != nil)) {
                Button("知道了") { problem = nil }
            } message: {
                Text(problem ?? "")
            }
        }
    }

    // MARK: - 群名

    private var header: some View {
        Section {
            HStack(spacing: 12) {
                Avatar(initial: conversation.friend.initial,
                       seed: conversation.friend.avatarSeed,
                       size: 52,
                       url: conversation.friend.avatarURL)

                if iAmOwner {
                    TextField("群名称", text: $title)
                        .font(.system(size: 17, weight: .medium))
                        .submitLabel(.done)
                        .onSubmit { Task { await rename() } }
                } else {
                    Text(conversation.friend.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if iAmOwner {
                Text("改完按回车生效。只有群主能改群名。")
            }
        }
    }

    // MARK: - 成员

    private var membersSection: some View {
        Section {
            ForEach(members) { member in
                HStack(spacing: 12) {
                    Avatar(initial: member.initial,
                           seed: member.avatarSeed,
                           size: 38,
                           url: member.avatarURL)

                    Text(member.name)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textPrimary)

                    if member.isOwner {
                        Text("群主")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accentSoft, in: Capsule())
                    }

                    Spacer(minLength: 0)

                    if member.id == store.myID {
                        Text("我")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                Haptics.tap()
                showAddMembers = true
            } label: {
                Label("加人进群", systemImage: "person.badge.plus")
                    .font(.system(size: 15))
            }
            .disabled(invitable.isEmpty)
        } header: {
            Text("群成员（\(members.count)）")
        }
    }

    // MARK: - 退群

    private var actionsSection: some View {
        Section {
            if iAmOwner {
                // 群主不给退群按钮 —— 直接给一句解释，
                // 而不是给一个点了会报错的按钮。
                Text("你是群主。转让给别人之后才能退群。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Button(role: .destructive) {
                    Haptics.tap()
                    showLeaveConfirm = true
                } label: {
                    HStack {
                        Text("退出群聊")
                        Spacer()
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func reload() async {
        members = await store.members(of: conversation.friend.id)
        title = conversation.friend.displayName
    }

    private func rename() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != conversation.friend.displayName else { return }
        isWorking = true
        do {
            try await store.renameGroup(conversation.friend.id, to: trimmed)
            Haptics.success()
        } catch {
            problem = "改群名失败：\(error.localizedDescription)"
            title = conversation.friend.displayName   // 改回去，别显示一个没生效的名字
        }
        isWorking = false
    }

    private func addMembers(_ picked: [Conversation]) async {
        let usernames = picked.map { $0.friend.username }.filter { !$0.isEmpty }
        guard usernames.count == picked.count else {
            problem = "有人的用户名还没同步下来，稍后再试。"
            return
        }
        isWorking = true
        do {
            try await store.addMembers(to: conversation.friend.id, usernames: usernames)
            Haptics.success()
            await reload()
        } catch {
            problem = "加人失败：\(error.localizedDescription)"
        }
        isWorking = false
    }

    private func leave() async {
        isWorking = true
        do {
            try await store.leaveGroup(conversation.friend.id)
            Haptics.success()
            dismiss()
            onLeft()
        } catch {
            problem = "退群失败：\(error.localizedDescription)"
        }
        isWorking = false
    }
}

/// 选人进群。和建群那个页面同一套交互：勾选 + 顶部按钮。
private struct AddMembersSheet: View {

    let candidates: [Conversation]
    let onConfirm: ([Conversation]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(candidates) { convo in
                Button {
                    Haptics.selection()
                    if picked.contains(convo.friend.id) {
                        picked.remove(convo.friend.id)
                    } else {
                        picked.insert(convo.friend.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        // 用勾而不是只靠背景色 —— 色弱用户也看得出来
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("加人进群")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("加入") {
                        let chosen = candidates.filter { picked.contains($0.friend.id) }
                        Task { await onConfirm(chosen) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}
