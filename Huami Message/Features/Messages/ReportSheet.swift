import SwiftUI

/// 举报面板。
///
/// 【审核上最容易被忽略的一点】
/// App Store 指南 1.2 条不只要"有一个举报按钮"。它要的是：
///   1. 有举报入口                     ✓ 这个面板
///   2. 有拉黑功能                     ✓ 聊天页的菜单
///   3. **说明举报之后会发生什么**       ← 很多人漏掉这条
///   4. **零容忍条款**（写明什么样的内容会被处理）  ← 也很多人漏掉
///
/// 第 3、4 条就在下面这个面板里写着。审核员打开看一眼就能确认，
/// 比藏在几层设置菜单里要安全得多。
struct ReportSheet: View {

    let friend: Friend

    /// 提交举报后的回调：(原因, 补充说明)
    var onSubmit: (ReportReason, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .harassment
    @State private var note = ""

    private var canSubmit: Bool {
        // 选"其他"时必须写点说明，否则我们拿到一条没法处理的举报
        reason != .other || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    targetCard
                    reasonCard
                    noteCard
                    policyCard
                    submitButton
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("举报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - 举报对象

    private var targetCard: some View {
        HStack(spacing: 12) {
            Avatar(initial: friend.initial, seed: friend.avatarSeed, size: 44, url: friend.avatarURL)
            VStack(alignment: .leading, spacing: 2) {
                Text("举报对象")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
        }
        .padding(14)
        .card(.subtle, radius: 16)
    }

    // MARK: - 原因

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("举报原因")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(ReportReason.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) { reason = item }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: reason == item ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(reason == item ? Theme.accent : Theme.textTertiary)
                        Text(item.title)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())   // 让整行都能点，而不是只有字能点
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .card()
    }

    // MARK: - 补充说明

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("补充说明")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if reason == .other {
                    Text("（选「其他」时必填）")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                }
            }

            TextEditor(text: $note)
                .font(.system(size: 15))
                // 去掉 TextEditor 默认的白底，否则毛玻璃就毁了
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 0.8)
                }
        }
        .padding(16)
        .card(.subtle, radius: 16)
    }

    // MARK: - 零容忍条款（审核要看的就是这一段）

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.mint)
                Text("我们会怎么处理")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            bullet("我们对以下内容**零容忍**：骚扰、色情、暴力、诈骗和垃圾信息。")
            bullet("举报会在 24 小时内被查看。核实后我们会封禁相关账号。")
            bullet("你可以同时把对方**拉黑**（这样他再也无法给你发消息）。")
            bullet("举报记录会保留，即使你之后删除了这个会话。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            // 用 LocalizedStringKey 让 **粗体** 这种 Markdown 生效
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 提交

    private var submitButton: some View {
        Button {
            Haptics.warning()
            onSubmit(reason, note.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } label: {
            Text("提交举报")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    canSubmit
                        ? AnyShapeStyle(Theme.danger)
                        : AnyShapeStyle(Theme.separator),
                    in: Capsule()
                )
        }
        .disabled(!canSubmit)
    }
}
