import Foundation

/// 假数据版的 AI 服务 —— 接真 AI 之前都用它。
///
/// ⚠️ 说清楚：它**不是真的 AI**，只是把预先写好的文字按节奏一段段吐出来。
/// 目的是让我们先把「流式输出」的手感调好（速度、光标、停顿），
/// 因为这部分体验和用哪家 AI 完全无关。
///
/// 等接入 DeepSeek 时，只换掉这个文件，
/// 界面和 ChatStore 一行都不用改 —— 因为大家都在 AIService 这个插座标准上。
final class MockAIService: AIService {

    // MARK: 模块一：润色（只看一句话）

    /// 假 AI —— 界面上会显示「演示模式」的提示
    let isDemoData = true

    func polish(_ text: String, style: PolishStyle) -> AsyncThrowingStream<String, Error> {
        // 演示用的三个版本。故意做得风格差异明显，好让你看清三种模式的区别。
        let demo: [PolishStyle: String] = [
            .tactful: "昨天没看到你，是临时有事吗？大家等到挺晚的，都有点担心你。",
            .concise: "昨天怎么没来？大家等了很久。",
            .warm:    "昨天没见到你，还有点担心。要是遇到什么事，随时跟我说。",
        ]
        // 一个字一个字地吐，45 毫秒一个 —— 这个速度最像「有人在打字」
        return Self.stream(demo[style] ?? "", chunk: 1, interval: .milliseconds(45))
    }

    // MARK: 模块二：小助手（看整段对话）

    func advise(context: AssistantContext, intent: AssistantIntent) -> AsyncThrowingStream<AssistantEvent, Error> {
        let name = context.friendName
        let model = Self.decisionModel(for: intent, friendName: name)

        return AsyncThrowingStream { continuation in
            let task = Task {
                // 先给一句状态提示 —— 什么都不显示地干等是最难受的
                continuation.yield(.status("正在读你和\(name)的这段对话"))

                // 然后一个方块一个方块地冒出来。
                // 每出来一个就有信息可读，所以"等待"的感觉和转圈完全不同。
                for block in model.blocks {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .milliseconds(420))
                    continuation.yield(.block(block))
                }

                if !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(320))
                    continuation.yield(.recommendation(model.recommendation))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 假数据：三种意图各给一套判断
    //
    // 【这里的内容不是随便编的，它就是将来要给 DeepSeek 的提示词的草稿】
    //
    // 真接上 AI 之后，这些方块的内容由模型生成，但**形状完全一样**。
    // 所以现在把"什么样的判断才算有用"想清楚，比急着接真模型重要得多。
    //
    // 几条我自己定的规矩：
    //   · 每个方块里的选项概率加起来必须等于 100
    //   · 至少有一个方块是"量级"（危险等级之类），因为人慌的时候需要一个刻度
    //   · 最后那条建议必须是**具体动作**，不能是"多沟通"这种废话

    private static func decisionModel(for intent: AssistantIntent,
                                      friendName: String) -> DecisionModel {
        switch intent {

        // ── 他什么意思 ──
        case .explain:
            return DecisionModel(
                blocks: [
                    DecisionBlock(
                        kind: .options,
                        prompt: "他是在等你解释吗？",
                        options: [
                            DecisionOption(label: "不是，他要的是态度", percent: 79, isRecommended: true),
                            DecisionOption(label: "是", percent: 21),
                        ]
                    ),
                    DecisionBlock(
                        kind: .options,
                        title: "这句话底下的意思",
                        prompt: "「你昨天怎么没来？大家都等你很久了」",
                        options: [
                            DecisionOption(label: "我为你留了时间，你没出现，我失望", percent: 68, isRecommended: true),
                            DecisionOption(label: "大家都在，你让我不好看", percent: 22),
                            DecisionOption(label: "单纯想知道原因", percent: 10),
                        ]
                    ),
                    DecisionBlock(
                        kind: .level,
                        prompt: "这件事的严重程度",
                        level: 6,
                        levelCaption: "危险等级"
                    ),
                    DecisionBlock(
                        kind: .options,
                        prompt: "现在解释原因有用吗？",
                        options: [
                            DecisionOption(label: "没用，听着像找借口", percent: 85, isRecommended: true),
                            DecisionOption(label: "有用", percent: 15),
                        ]
                    ),
                    DecisionBlock(
                        kind: .options,
                        title: "最好的下一步",
                        prompt: "你现在该做什么",
                        options: [
                            DecisionOption(label: "先认下这件事", percent: 74, isRecommended: true),
                            DecisionOption(label: "先问清楚当时的情况", percent: 18),
                            DecisionOption(label: "等他自己消气", percent: 8),
                        ]
                    ),
                ],
                recommendation: "回的时候先接住情绪，再讲事实。**第一句里不要出现「因为」**。",
                sharedMessageCount: 0
            )

        // ── 我该怎么回 ──
        case .reply:
            return DecisionModel(
                blocks: [
                    DecisionBlock(
                        kind: .options,
                        prompt: "需要马上回吗？",
                        options: [
                            DecisionOption(label: "需要", percent: 88, isRecommended: true),
                            DecisionOption(label: "可以缓一缓", percent: 12),
                        ]
                    ),
                    DecisionBlock(
                        kind: .level,
                        prompt: "这件事的紧急程度",
                        level: 7,
                        levelCaption: "紧急程度"
                    ),
                    DecisionBlock(
                        kind: .options,
                        title: "这条回复的重点",
                        prompt: "他其实在等哪一句",
                        options: [
                            DecisionOption(label: "认下「没到」这件事", percent: 71, isRecommended: true),
                            DecisionOption(label: "说明当时的原因", percent: 19),
                            DecisionOption(label: "把话题带过去", percent: 10),
                        ]
                    ),
                    DecisionBlock(
                        kind: .options,
                        prompt: "「我不知道怎么解释」这种回答他能接受吗？",
                        options: [
                            DecisionOption(label: "不能", percent: 76, isRecommended: true),
                            DecisionOption(label: "能", percent: 24),
                        ]
                    ),
                    DecisionBlock(
                        kind: .options,
                        title: "推荐的开头",
                        prompt: "第一句怎么说",
                        options: [
                            DecisionOption(label: "抱歉，昨天确实没到", percent: 64, isRecommended: true),
                            DecisionOption(label: "昨天临时出了点事", percent: 26),
                            DecisionOption(label: "等我很久了吧？", percent: 10),
                        ]
                    ),
                ],
                recommendation: "先认下「没到」这件事，理由放到第二句。**「因为」两个字越晚出现越好**。",
                sharedMessageCount: 0
            )

        // ── 帮我起草 ──
        case .draft:
            return DecisionModel(
                blocks: [
                    DecisionBlock(
                        kind: .options,
                        prompt: "这件事需要你先开口吗？",
                        options: [
                            DecisionOption(label: "需要", percent: 82, isRecommended: true),
                            DecisionOption(label: "可以再等等", percent: 18),
                        ]
                    ),
                    DecisionBlock(
                        kind: .options,
                        title: "先开口的代价",
                        prompt: "你在担心什么",
                        options: [
                            DecisionOption(label: "可能被追问细节", percent: 47),
                            DecisionOption(label: "其实不丢面子，反而显得在意", percent: 42, isRecommended: true),
                            DecisionOption(label: "显得我心虚", percent: 11),
                        ]
                    ),
                    DecisionBlock(
                        kind: .level,
                        prompt: "开口的难度",
                        level: 5,
                        levelCaption: "开口难度"
                    ),
                    DecisionBlock(
                        kind: .options,
                        title: "起头的三种方式",
                        prompt: "哪种最不容易把话说僵",
                        options: [
                            DecisionOption(label: "直接认下那件事", percent: 58, isRecommended: true),
                            DecisionOption(label: "先说自己的感受", percent: 27),
                            DecisionOption(label: "先问对方方不方便说", percent: 15),
                        ]
                    ),
                ],
                recommendation: "开头别绕。第一句就把那件事说出来，比如「\(friendName)，昨天的事是我不对」。**越绕越像心虚**。",
                sharedMessageCount: 0
            )
        }
    }

    // MARK: - 流式输出的引擎

    /// 把一段文字切成小块，每隔一段时间吐一块。
    ///
    /// 这就是「打字机效果」的本质 —— 它不是动画，是数据真的在一段段到达。
    /// 这个区别很重要：动画是你先有完整文字、再假装它慢慢出现；
    /// 流式是你真的只拿到了前半句。后者才是接真 AI 时必须的做法，
    /// 所以我们从一开始就用真的。
    private static func stream(_ text: String, chunk: Int, interval: Duration) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var index = text.startIndex
                while index < text.endIndex, !Task.isCancelled {
                    let end = text.index(index, offsetBy: chunk, limitedBy: text.endIndex) ?? text.endIndex
                    continuation.yield(String(text[index..<end]))
                    index = end
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            // 界面中途关掉（比如用户点了取消）时，把这个循环也停掉，别白烧 CPU
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
