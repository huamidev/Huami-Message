import SwiftUI

/// 小助手面板。
///
/// 【这一版改了什么，为什么】
///
/// 原来用户要：点悬浮图标 → 打开面板 → 再点一次"帮我看看"。
/// 现在用户点的是**一个具体问题**（"他什么意思？"/"我该怎么回？"），
/// 面板打开就已经在跑了 —— 少一步，而且不用自己组织语言描述需求。
///
/// 代价是"发送"这个动作提前到了点击选项的那一刻。所以：
///   · 选项所在的小方块上**一直写着**"会把最近 N 条消息发给 AI"
///   · 面板顶部把**本次真正发送的内容**原样列出来
/// 这样用户点之前知道会发生什么，点之后也能核对 —— 仍然是知情同意。
struct AssistantSheet: View {

    let context: AssistantContext
    let intent: AssistantIntent

    /// 用户选了某条建议 → 填回输入框（不自动发送）
    var onUseReply: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let ai = MockAIService()

    @State private var analysis = ""
    @State private var suggestions: [String] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contextCard
                    if analysis.isEmpty { thinkingCard } else { analysisCard }
                    if !suggestions.isEmpty { suggestionsCard }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(intent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onDisappear { task?.cancel() }
        // 进来自动开始 —— 用户点那个选项，本身就已经是"我要问这个"的意思了
        .task { start() }
    }

    // MARK: - 本次发送了什么（放在最上面，让用户可以核对）

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.mint)
                Text("本次发送给 AI 的内容")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("你和\(context.friendName)最近 \(context.messages.count) 条消息")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            if let last = context.lastFriendMessage {
                // 把"对方最后说的那句"原样贴出来 ——
                // 用户一眼就能确认"对，就是这一段"，而不是笼统地相信我们
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.5))
                        .frame(width: 2)
                    Text(last.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card(.subtle, radius: 14)
    }

    // MARK: - 还在想

    private var thinkingCard: some View {
        HStack(spacing: 8) {
            StreamingCaret()
            Text("正在想…")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(16)
        .card()
    }

    // MARK: - 分析（流式）

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(intent.heading)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            // 用 LocalizedStringKey 让文本里的 **粗体** 生效
            Text(LocalizedStringKey(analysis))
                .font(.system(size: 15))
                // 行距调大一点。中文长段落挤在一起很难读，
                // 这一行对"读起来舒不舒服"的影响比换字体还大。
                .lineSpacing(5)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .card()
    }

    // MARK: - 可以直接用的句子

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(intent == .draft ? "挑一个往下写" : "挑一个发出去")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, text in
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Haptics.selection()
                        // 只填回输入框，不自动发送。
                        // 发消息是不可撤销的动作，决定权必须留给人。
                        onUseReply(text)
                        dismiss()
                    } label: {
                        Text("用这个")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .card(.subtle)
            }
        }
        .padding(16)
        .card()
        // 建议是"文字吐完之后一次性给"的，所以它出现时会突然多出来一块。
        // 加个动画，让它滑进来而不是"啪"地跳出来。
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - 动作

    private func start() {
        guard task == nil else { return }

        task = Task {
            for await event in ai.advise(context: context, intent: intent) {
                if Task.isCancelled { break }
                switch event {
                case .analysis(let chunk):
                    analysis += chunk
                case .suggestions(let list):
                    withAnimation(.snappy(duration: 0.3)) {
                        suggestions = list
                    }
                }
            }
            if !Task.isCancelled { Haptics.success() }
        }
    }
}
