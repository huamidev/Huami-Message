import SwiftUI

/// 小助手面板 —— 「AI 好友」这一模块的新形态。
///
/// 【为什么它不再是一个独立的 Tab】
///
/// 它的工作是「看懂对方说的话，帮你想怎么回」。
/// 那它就该待在**对话发生的那个界面里** ——
/// 让用户把对方的话复制出来、切到另一个 Tab、再粘进去，是白白多出来的两步。
///
/// 现在它就是聊天页里一个悬浮的小按钮，点开就是这个面板：
/// 它已经看得见你正在聊的这段对话，不用你复制粘贴。
///
/// 【隐私上守的两条底线】
///   1. **必须用户主动点两次**（点开小助手 + 再点"帮我看看"）才会发送对话内容
///   2. 发送前把"要发哪一段"直接显示出来，让用户点之前就知道
///
/// 这是「知情同意」，不是「默认同意」。这两者差别很大。
struct AssistantSheet: View {

    let context: AssistantContext

    /// 用户选了某条建议 → 填回输入框（不自动发送）
    var onUseReply: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let ai = MockAIService()

    @State private var analysis = ""
    @State private var suggestions: [String] = []
    @State private var isThinking = false
    @State private var task: Task<Void, Never>?

    private var hasResult: Bool { !analysis.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    privacyCard

                    if !hasResult {
                        startButton
                    } else {
                        analysisCard
                        if !suggestions.isEmpty { suggestionsCard }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("小助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onDisappear { task?.cancel() }
        // 开发用：带 -assistantGo 1 时自动开始，省掉手动点击（为了截图/验证）
        .task {
            if DevFlags.assistantGo { start() }
        }
    }

    // MARK: - 发送之前先说清楚要发什么

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.mint)
                Text("点「帮我看看」时，会发送这些内容")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("你和\(context.friendName)最近 \(context.messages.count) 条消息")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

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

            Text("发送前请确认这段对话里没有你不想让别人看到的信息。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    // MARK: - 开始

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("帮我看看怎么回")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.myBubbleGradient, in: Capsule())
        }
        .disabled(isThinking)
        .opacity(isThinking ? 0.6 : 1)
    }

    // MARK: - 分析（流式）

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.warning)
                Text("他是这个意思")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isThinking { StreamingCaret() }
            }

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

    // MARK: - 可以这样回

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可以这样回")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, text in
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
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
        // 建议是"分析完之后一次性给"的，所以它出现时会突然多出来一块。
        // 加个动画，让它滑进来而不是"啪"地跳出来。
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - 动作

    private func start() {
        guard !isThinking, analysis.isEmpty else { return }
        isThinking = true

        task?.cancel()
        task = Task {
            for await event in ai.advise(context: context) {
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
            isThinking = false
        }
    }
}
