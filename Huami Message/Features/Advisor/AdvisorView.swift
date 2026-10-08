import SwiftUI

/// 「军师」页 —— 模块二。
///
/// 【它和模块一的界限，这是产品设计上必须守住的一条线】
///
///   模块一（聊天框旁边的润色）= **修**。改你正在打的这**一句话**。轻、快、单句。
///   模块二（这一页）          = **想**。帮你判断**整件事**。可以长篇、可以贴一整段对话。
///
/// 为什么不做「通用陪聊」：那等于又一个 ChatGPT 套壳，
/// 审核容易按 4.3 条（重复/垃圾应用）打回，
/// 而且它和产品定位是反的 —— 「帮你把话说好」不该变成「帮你不用跟人说话」。
struct AdvisorView: View {

    @State private var situation = ""
    @State private var answer = ""
    @State private var isThinking = false
    @State private var task: Task<Void, Never>?

    private let ai = MockAIService()

    @FocusState private var editorFocused: Bool

    private var canAnalyze: Bool {
        !situation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    var body: some View {
        NavigationStack {
            AppPage {
                ScrollView {
                    VStack(spacing: 16) {
                        introCard
                        inputCard
                        if !answer.isEmpty {
                            answerCard
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("军师")
        }
        .onDisappear { task?.cancel() }
    }

    // MARK: - 顶部说明

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("帮你把话想清楚")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("把对方说的话贴进来，军师帮你分析他真正的意思，再给你几个可以怎么回的方向。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.separator)

            Text("聊天框旁边的「润色」改的是你正在打的那一句话；这里帮你想的是整件事该怎么办。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(.subtle)
    }

    // MARK: - 输入区

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("对方说了什么")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ZStack(alignment: .topLeading) {
                // 自己画占位文字，因为 TextEditor 没有原生的 placeholder
                if situation.isEmpty {
                    Text("比如：你昨天怎么没来？大家都等你很久了，你这样不太好吧。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)   // 别挡住点击，否则点不进去
                }

                TextEditor(text: $situation)
                    .font(.system(size: 15))
                    // 去掉 TextEditor 默认的白色背景。
                    // 不去掉的话它就是一块白板子，毛玻璃全毁了 —— 这是新手最常踩的坑之一。
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .focused($editorFocused)
            }
            .padding(8)
            .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 0.8)
            }

            Button(action: analyze) {
                HStack(spacing: 6) {
                    Image(systemName: isThinking ? "ellipsis" : "sparkles")
                    Text(isThinking ? "正在想…" : "帮我分析")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.myBubbleGradient, in: Capsule())
            }
            .disabled(!canAnalyze)
            .opacity(canAnalyze ? 1 : 0.45)
            .animation(.snappy(duration: 0.2), value: canAnalyze)
        }
        .padding(16)
        .card()
    }

    // MARK: - 结果区（流式输出）

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.warning)
                Text("军师的分析")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if isThinking { StreamingCaret() }
            }

            Text(answer)
                .font(.system(size: 15))
                // 行距调大一点。中文长段落挤在一起很难读，
                // 这一行代码对「读起来舒不舒服」的影响比换字体还大。
                .lineSpacing(5)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .card()
    }

    // MARK: - 动作

    private func analyze() {
        editorFocused = false
        answer = ""
        isThinking = true

        task?.cancel()
        task = Task {
            for await chunk in ai.advise(situation) {
                if Task.isCancelled { break }
                answer += chunk
            }
            isThinking = false
        }
    }
}
