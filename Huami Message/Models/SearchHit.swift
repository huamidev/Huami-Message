import Foundation

/// 一条搜索结果。
///
/// 【为什么好友和消息共用一种类型】
///
/// 因为用户搜索的时候**心里没有分类** —— 他输入"周五"，
/// 既可能是想找老周这个人，也可能是想找那句话。
/// 分成两个列表让他自己挑，是把这个判断推给用户。
///
/// 合成一个列表、按相关度排，更接近"搜索"这件事本来的样子。
struct SearchHit: Identifiable, Hashable {

    enum Kind: Hashable {
        case friend    // 命中了这个人的名字
        case message   // 命中了这句话的内容
    }

    let id: String
    let kind: Kind
    let friend: Friend

    /// 命中的文字：好友名，或者那句话
    let text: String

    /// 消息的时间（好友命中时为 nil）
    let date: Date?

    /// 为什么把"最新"排前面：搜到的东西里，
    /// **最近发生的更可能是你要找的** —— 人回忆事情是按时间倒着来的。
    var sortKey: Date { date ?? .distantFuture }
}
