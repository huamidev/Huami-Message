import Foundation

// MARK: - 助手要看的上下文

/// 交给助手的一段对话。
///
/// 【关于隐私，这里要说清楚】
///
/// 润色（输入框旁边那个 ✨）**只发送你正在打的那一句话**，从不读聊天记录 ——
/// 这是你早先定下的原则，一直没变。
///
/// 但「小助手」不一样：它要分析对方说的话，**就必须看得到对话**。
/// 所以这里只做两件事来守住底线：
///   1. **只有用户主动点开小助手、并且再点一次"帮我看看"才会构造这个上下文** ——
///      绝不在后台偷偷读取
///   2. 界面上明确写出"会发送最近几条消息"，让用户点之前就知道
///
/// 这是"知情同意"，不是"默认同意"。两者差别很大。
struct AssistantContext {

    /// 对方的名字（让分析读起来能自然地称呼他）
    let friendName: String

    /// 要读的消息，从早到晚排列
    let messages: [Message]

    /// 对方最后说的话。
    /// 界面上会把它显示出来 —— 让用户清楚"即将发送的是哪一段"。
    var lastFriendMessage: Message? {
        messages.last { $0.sender == .friend }
    }

    /// 最多发送多少条消息。
    ///
    /// 限制条数不是为了省流量，是**为了少发一点隐私**：
    /// 判断"对方这句话什么意思"根本用不着三个月的聊天记录。
    /// 能少发就少发 —— 这是处理别人聊天内容时该有的自觉。
    static let recentLimit = 10
}

// MARK: - 助手能干的几种事

/// 用户想让小助手做什么。
///
/// 【为什么要做成枚举，而不是让用户自己描述】
///
/// 想找小助手的人，心里其实已经有一个**具体问题**了：
/// "他这话到底什么意思"、"我该怎么回"、"帮我起个头"。
///
/// 与其让他点开一个面板、再打字描述需求，不如把这几个问题直接摆在面前 ——
/// **少一步，而且不用组织语言**。这也顺便把提示词固定下来了：
/// 每种意图对应一套明确的指令，比让用户自由发挥稳定得多。
enum AssistantIntent: String, CaseIterable, Identifiable, Codable {

    case explain   // 他什么意思
    case reply     // 我该怎么回
    case draft     // 帮我起草

    var id: String { rawValue }

    /// 摆在小方块里的按钮文字。要短，一眼扫得完。
    var title: String {
        switch self {
        case .explain: "他什么意思？"
        case .reply:   "我该怎么回？"
        case .draft:   "帮我起草"
        }
    }

    /// 进面板后的标题（比按钮文字可以说得更完整）
    var heading: String {
        switch self {
        case .explain: "他是这个意思"
        case .reply:   "可以这样回"
        case .draft:   "给你起了个头"
        }
    }
}

// 小助手吐出来的东西（AssistantEvent）以及决策模型的结构，
// 都定义在 Models/DecisionModel.swift 里 —— 那些是**数据形状**，
// 不属于"AI 服务"这一层。

// MARK: - AI 服务

/// AI 服务的「插座标准」。
///
/// 【为什么润色和助手是两个方法，而不是一个通用的「问 AI」？】
///
/// 因为它们背后是两套完全不同的提示词和两套不同的产品逻辑：
///   · polish：改一句话。要求「最小改动、保留原意、只调语气」，**不看聊天记录**
///   · advise：看一段对话。要求「先分析对方意图，再给出可选回复方向」
///
/// 混成一个接口，将来调提示词一定会互相污染，改 A 弄坏 B。
protocol AIService {

    /// 润色一句话。
    /// 注意：这里**只传一句话，不传聊天记录** —— 这是刻意的隐私设计。
    func polish(_ text: String, style: PolishStyle) -> AsyncStream<String>

    /// 小助手：看一段对话，按指定的意图给出判断。
    ///
    /// 返回的是一串事件：状态提示 → 一个一个小方块 → 最后的建议动作。
    /// 拆成事件是为了让方块**一个一个冒出来**，而不是让用户对着转圈等好几秒。
    func advise(context: AssistantContext, intent: AssistantIntent) -> AsyncStream<AssistantEvent>
}
