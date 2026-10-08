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

    func polish(_ text: String, style: PolishStyle) -> AsyncStream<String> {
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

    func advise(context: AssistantContext) -> AsyncStream<AssistantEvent> {
        let name = context.friendName
        let quoted = String((context.lastFriendMessage?.text ?? "").prefix(24))

        // 分析部分。
        // 刻意写得像"人话"，而且真的引用了对方最后那句话 ——
        // 这样你看着能判断这个交互对不对，而不是对着一堆废话找不到感觉。
        let analysis = """
        先别急着解释。\(name)最后那句是「\(quoted)」，重点其实不在字面上。

        这句话底下压着两件事：一是「我为你留了时间，你没出现」—— 这是失望；
        二是把压力从一个人变成了一群人 —— 这是让你不好反驳。

        所以他真正想听的不是理由，而是「我知道这件事对你重要」。
        顺序很关键：**先接住情绪，再讲事实**。反过来就一定吵起来。
        """

        // 三条可以直接用的回复
        let suggestions = [
            "抱歉，昨天确实没到。我知道你们等了很久，这事是我不对。",
            "昨天临时出了点事走不开，没来得及跟你们讲，对不起。",
            "等我很久了吧？昨天实在脱不开身，回头我请你们吃饭赔罪。",
        ]

        return AsyncStream { continuation in
            let task = Task {
                // 先流式吐分析
                for await chunk in Self.stream(analysis, chunk: 3, interval: .milliseconds(18)) {
                    if Task.isCancelled { break }
                    continuation.yield(.analysis(chunk))
                }
                // 分析吐完了，再一次性给建议
                continuation.yield(.suggestions(suggestions))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 流式输出的引擎

    /// 把一段文字切成小块，每隔一段时间吐一块。
    ///
    /// 这就是「打字机效果」的本质 —— 它不是动画，是数据真的在一段段到达。
    /// 这个区别很重要：动画是你先有完整文字、再假装它慢慢出现；
    /// 流式是你真的只拿到了前半句。后者才是接真 AI 时必须的做法，
    /// 所以我们从一开始就用真的。
    private static func stream(_ text: String, chunk: Int, interval: Duration) -> AsyncStream<String> {
        AsyncStream { continuation in
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
