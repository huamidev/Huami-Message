import SwiftUI

/// AI 润色面板 —— 你在第一步选定的「多版本候选」方案。
///
/// 交互上有两个决定，我解释一下为什么这么做：
///
/// ① **一次给三个版本让你选，而不是 AI 改好直接塞回去。**
///    「这句话怎么说才得体」没有标准答案，只有「你想要的答案」。
///    让 AI 出选项、你来拍板，出错概率最低，
///    而且用户会觉得是自己在掌控，而不是被 AI 摆布。
///
/// ② **选中的版本只填回输入框，不自动发送。**
///    你还有机会改一改。发消息不可撤销，这个决定权必须留给人。
struct PolishSheet: View {

    /// 用户在输入框里原本写的话
    let original: String

    /// 选中某个版本后的回调：(改好的文字, 用的哪种风格)
    var onPick: (String, PolishStyle) -> Void

    @Environment(\.dismiss) private var dismiss

    private let ai = MockAIService()

    /// 每个风格当前已经「长」出来的文字
    @State private var streamed: [PolishStyle: String] = [:]
    /// 每个风格是不是已经输出完了
    @State private var finished: Set<PolishStyle> = []
    /// 记住这三个流，页面关掉时把它们一起停掉，别在后台空转
    @State private var tasks: [Task<Void, Never>] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    demoBadge
                    originalCard

                    ForEach(PolishStyle.allCases) { style in
                        variantCard(style)
                    }

                    privacyNote
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("AI 润色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .task { startStreaming() }
        .onDisappear { tasks.forEach { $0.cancel() } }
    }

    // MARK: - 流式输出

    private func startStreaming() {
        // 三个风格**同时**开始，你会看到三张卡片一起「长字」。
        // 如果串行跑，用户要等三倍时间，而且没有「AI 正在全力工作」的丰富感。
        tasks = PolishStyle.allCases.map { style in
            Task { await pump(style) }
        }
    }

    private func pump(_ style: PolishStyle) async {
        for await chunk in ai.polish(original, style: style) {
            streamed[style, default: ""] += chunk
        }
        finished.insert(style)
    }

    // MARK: - 各个卡片

    /// 诚实很重要：现在还不是真 AI，界面上必须说清楚，
    /// 否则你自己测试时会被误导，以后给朋友测试也会被吐槽。
    private var demoBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text("演示模式：下面三个版本是预置示例，AI 还没接入")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.warning.opacity(0.12), in: Capsule())
    }

    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("你写的")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            // 万一 original 是空的（比如被程序调用时没传），也别显示一个空盒子 ——
            // 给一句提示，比让人盯着空白猜要好。
            Text(original.isEmpty ? "（没有拿到原文，请重新输入后再点润色）" : original)
                .font(.system(size: 15))
                .foregroundStyle(original.isEmpty ? Theme.textTertiary : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card(.subtle, radius: 16)
    }

    private func variantCard(_ style: PolishStyle) -> some View {
        let text = streamed[style] ?? ""
        let done = finished.contains(style)

        return VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 9) {
                Image(systemName: style.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(style.tint)
                    .frame(width: 27, height: 27)
                    .background(style.tint.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(style.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }

            // 正在输出的地方：文字 + 一闪一闪的光标
            HStack(alignment: .bottom, spacing: 3) {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !done && !text.isEmpty {
                    StreamingCaret()
                }
            }
            .frame(minHeight: 40, alignment: .topLeading)

            // 输出完了才出现「用这个」按钮。
            // 半成品不能选 —— 否则用户会点到一个只写了一半的版本。
            if done {
                Button {
                    onPick(text, style)
                    dismiss()
                } label: {
                    Text("用这个")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(style.tint.opacity(0.9), in: Capsule())
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(14)
        .card()
        .animation(.snappy(duration: 0.3), value: done)
    }

    /// 把你做的隐私承诺**写在界面上**，而不是藏在设置里。
    /// 藏在设置里的隐私承诺等于没有 —— 用户看不到，就不会相信。
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.mint)
            Text("润色只发送你正在打的这一句话，不会发送你和好友的聊天记录。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .card(.subtle, radius: 16)
    }
}
