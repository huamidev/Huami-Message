import Foundation

/// 假数据版的 AI 服务 —— 第 0 步专用。
///
/// ⚠️ 说清楚：它**不是真的 AI**，只是把预先写好的文字按节奏一段段吐出来。
/// 目的是让我们先把「流式输出」的手感调好（速度、光标、停顿），
/// 因为这部分体验和用哪家 AI 完全无关。
///
/// 等第 2 步接入 DeepSeek 时，只换掉这个文件，
/// 界面和 ChatStore 一行都不用改 —— 因为大家都在 AIService 这个插座标准上。
final class MockAIService: AIService {

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

    func advise(_ situation: String) -> AsyncStream<String> {
        // 把你贴的原话引一句，让它读起来像是真的在回应你
        let quoted = situation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(40)

        let text = """
        先别急着解释。你贴的是「\(quoted)」。

        这句话表面在问你为什么没来，底下其实压着两件事：

        一是「我为你留了时间，你没出现」—— 这是失望。
        二是「大家都等你」—— 这是把压力从一个人变成了一群人。

        所以他真正想听的不是理由，而是「我知道这件事对你重要」。

        给你三个方向：

        ① 先认情绪，再讲事实
           「抱歉，昨天确实没到。我知道你们等了很久，这事是我不对。」
           原因放在后面说。情绪先接住，理由才听得进去。

        ② 如果原因不方便细说
           「昨天临时出了点事走不开，没来得及跟你们讲，对不起。」
           不必编细节，说得过去就行。

        ③ 如果你们关系够近，可以先反问
           「等我很久了吧？昨天实在脱不开身。」

        要避开的一种回法：
           「我不是说了吗」／「你也知道我最近很忙」
           —— 哪怕是真的，这句话一出去，对方听到的是「你的时间没我的重要」。
        """
        // 一次吐 3 个字，20 毫秒一次 —— 比润色快一些，
        // 因为这段文字长，太慢会让用户等得心焦
        return Self.stream(text, chunk: 3, interval: .milliseconds(20))
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
