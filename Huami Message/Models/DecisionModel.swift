import Foundation

// ============================================================================
// 决策模型
// ============================================================================
//
// 【这是什么】
//
// 小助手的输出**不是一段话**，而是几个小方块。
// 每个方块回答一个问题，里面是几个候选项 + 各自的概率，
// 最后给一个量级（比如危险等级）和一个建议动作。
//
// 为什么这样比"讲一段道理"好用：
//
//   1. **逼着 AI 表态**。"他可能是这个意思，也可能是那个意思"这种话没有用；
//      让人给出 72% / 8% / 20%，就必须选一个主要解释。
//   2. **一眼能看完**。人在不知道怎么回消息的那一刻是慌的，没耐心读三段分析。
//   3. **概率是诚实的表达**。AI 本来就不可能确定别人在想什么，
//      用百分比反而比用肯定句更诚实。
//
// ============================================================================

/// 一个候选项，比如「想确认你在不在乎她 72%」
struct DecisionOption: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// 选项文字
    var label: String
    /// 概率，0-100
    var percent: Int
    /// 是不是推荐的那一项（界面上会高亮）
    var isRecommended: Bool = false

    /// 概率高低决定显示强度。高概率的选项要一眼看得见。
    var isStrong: Bool { percent >= 50 }
}

/// 一个小方块。
///
/// 【一个很坑的 Swift 细节，值得记下来】
///
/// 下面这些属性写了默认值（`var id = UUID()`、`var options = []`），
/// 但**自动合成的解码器会忽略这些默认值** —— 它照样要求 JSON 里有这些字段。
/// 默认值只在用 `init()` 构造时生效。
///
/// 结果是：服务器发来的 JSON 里没有 `id`（那是客户端自己用的），
/// 解码直接失败，界面上一个方块都出不来。
/// 日志里只会看到一个"看不懂的方块"，很难联想到是默认值的问题。
///
/// 所以下面在 extension 里自己写了一个解码器：
/// 能缺的字段就缺，缺了用默认值补。
/// （放在 extension 里是为了保住自动生成的 init —— 
///   写在本体里会让那个 init 消失，假数据那边就用不了了。）
struct DecisionBlock: Identifiable, Codable, Hashable {

    enum Kind: String, Codable {
        /// 一组选项 + 概率（最常用）
        case options
        /// 一个量级，比如「危险等级 9 / 10」
        case level
    }

    var id: UUID = UUID()

    var kind: Kind

    /// 可选的小标题，比如「当前真实意图」。
    /// 有些方块不需要标题（就一句话），所以是可选。
    var title: String?

    /// 方块里的那一句问题，比如「她真的在问"你记不记得"吗？」
    var prompt: String

    /// kind == .options 时的选项
    var options: [DecisionOption] = []

    /// kind == .level 时的量级（0-10）
    var level: Int?

    /// kind == .level 时量级代表什么，比如「危险等级」
    var levelCaption: String?
}

extension DecisionBlock {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 服务器不会发 id（那是客户端自己用的），缺了就自己生成一个
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        kind = try container.decode(Kind.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        options = (try? container.decode([DecisionOption].self, forKey: .options)) ?? []
        level = try container.decodeIfPresent(Int.self, forKey: .level)
        levelCaption = try container.decodeIfPresent(String.self, forKey: .levelCaption)
    }
}

extension DecisionOption {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        label = try container.decode(String.self, forKey: .label)
        percent = try container.decode(Int.self, forKey: .percent)
        // 服务器只在"推荐的"那一项上发这个字段，缺了就当 false
        isRecommended = (try? container.decode(Bool.self, forKey: .isRecommended)) ?? false
    }
}

/// 小助手一次完整的判断。
struct DecisionModel: Codable, Hashable {

    /// 几个小方块，按顺序显示
    var blocks: [DecisionBlock]

    /// 最后那条建议动作，比如「立即停止模型调用，不要画蛇添足」
    var recommendation: String

    /// 这次一共把多少条消息发给了 AI（界面上要如实告诉用户）
    var sharedMessageCount: Int
}

// ============================================================================
// 助手吐出来的东西
// ============================================================================

/// 小助手在流式输出的过程中，会一段段吐出这几种东西。
///
/// 【为什么不是"一次给一个完整的 DecisionModel"】
///
/// 因为那样用户要盯着一个转圈等好几秒。拆成事件之后，
/// **方块可以一个一个地冒出来** —— 每出来一个就有信息可读，
/// 等待感完全不同。
///
/// 这也是"流式"在结构化输出上的形态：
/// 文字流式是"一个字一个字"，这里是"一个方块一个方块"。
enum AssistantEvent {
    /// 一句状态提示，比如「正在读这段对话」
    case status(String)
    /// 冒出一个方块
    case block(DecisionBlock)
    /// 最后那条建议
    case recommendation(String)
}
