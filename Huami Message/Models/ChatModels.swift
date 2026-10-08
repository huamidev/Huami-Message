import SwiftUI

// MARK: - 发送状态

/// 一条消息的发送状态。
///
/// 为什么必须有这个东西：真实网络**一定会失败**（地铁里、电梯里、对方不在线）。
/// 如果一条消息发出去就"看起来成功了"，用户会以为对方收到了 ——
/// 这是聊天 App 里最让人恼火的一类 bug，也是"不丝滑"的根源之一。
///
/// 所以每条自己发的消息都要有一个明确的状态，并且**失败时能重试**。
enum MessageStatus: String, Codable, Hashable {
    case sending   // 发送中：本地已经显示了，正在往服务器送
    case sent      // 已送达服务器
    case failed    // 发送失败：界面上会出现一个可以点的重试按钮
}

// MARK: - 举报

/// 举报的原因。
///
/// 这不是"锦上添花"的功能，而是 App Store 审核指南 1.2 条的**硬性要求**：
/// 只要 App 里用户之间能互相发消息，就必须提供举报入口。
/// 没有它，TestFlight 的 Beta 审核就会被拒。
///
/// 选项也是照着苹果的常见要求来的：骚扰、色情、暴力、欺诈、垃圾信息。
enum ReportReason: String, CaseIterable, Identifiable, Codable {
    case harassment
    case porn
    case violence
    case fraud
    case spam
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: "骚扰或辱骂"
        case .porn:       "色情或低俗内容"
        case .violence:   "暴力或威胁"
        case .fraud:      "诈骗或虚假信息"
        case .spam:       "广告或垃圾信息"
        case .other:      "其他"
        }
    }
}

/// 一条举报记录。
///
/// 现在只存在本地。接上 Supabase 之后，这里会多一步"上报到服务器"。
/// 先把数据结构定下来，是为了以后不用改界面。
struct Report: Identifiable, Hashable {
    let id: UUID
    var friendID: Friend.ID
    var reason: ReportReason
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        friendID: Friend.ID,
        reason: ReportReason,
        note: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.friendID = friendID
        self.reason = reason
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - 好友

/// 一个真实好友。
///
/// 注意这里存的是 avatarSeed（一个数字）而不是颜色。
/// 原因：好友信息要从数据库和服务器来，颜色是存不进去的，但数字可以。
/// 头像颜色由这个数字在界面上现算出来。
struct Friend: Identifiable, Hashable {
    let id: UUID
    var name: String
    var avatarSeed: Int

    init(id: UUID = UUID(), name: String, avatarSeed: Int) {
        self.id = id
        self.name = name
        self.avatarSeed = avatarSeed
    }

    /// 名字的第一个字，暂时当头像用
    var initial: String { String(name.prefix(1)) }
}

// MARK: - 消息

/// 一条消息。这是整个 App 最核心的数据结构。
struct Message: Identifiable, Hashable {

    /// 谁发的
    enum Sender: Hashable {
        case me      // 我发的
        case friend  // 好友发的
    }

    let id: UUID

    /// 这条消息属于哪个好友的会话。
    ///
    /// 说明：第一版只做一对一，所以用 friendID 就够了。
    /// 以后要做群聊的话，这里要换成 conversationID —— 到时候我会提醒你。
    var friendID: Friend.ID

    var text: String

    /// 图片消息的图片地址。纯文字消息是 nil。
    ///
    /// 【为什么文字和图片共用一个类型，而不是分成两种消息】
    ///
    /// 因为它们在界面上**是同一种东西**：一条气泡、一个时间、一个发送状态。
    /// 分开之后，排序、分页、未读数、撤回、搜索……每一处都要写两遍。
    /// 「一条消息可以带张图」比「有两种消息」简单得多。
    ///
    /// 带图的消息 text 是空字符串 —— 不是 nil，因为界面上"没有文字"
    /// 和"文字是空的"没有区别，多一个可选值只会让每处都多一层解包。
    var imageURL: URL?

    var sender: Sender
    var sentAt: Date

    /// 这条消息是不是经过 AI 润色的、用了哪种风格。
    ///
    /// 界面上会在气泡下面显示一个小标记，让用户清楚地知道
    /// 「这条不是我原话」。这是「用户知情」——
    /// 既是产品伦理，也是上架审核会看的东西。
    var polishedWith: PolishStyle?

    /// 发送状态。好友发来的消息永远是 .sent，不用管这个字段。
    var status: MessageStatus

    init(
        id: UUID = UUID(),
        friendID: Friend.ID,
        text: String,
        imageURL: URL? = nil,
        sender: Sender,
        sentAt: Date = .now,
        polishedWith: PolishStyle? = nil,
        status: MessageStatus = .sent
    ) {
        self.id = id
        self.friendID = friendID
        self.text = text
        self.imageURL = imageURL
        self.sender = sender
        self.sentAt = sentAt
        self.polishedWith = polishedWith
        self.status = status
    }
}

// MARK: - 会话

/// 会话列表里的一行。
///
/// 它自己不存消息，只存「最后一条的摘要」。真正的消息在
/// ChatStore.messagesByFriend 里按好友分开存。
struct Conversation: Identifiable, Hashable {

    /// 会话的 id 就是好友的 id（因为第一版只有一对一）。
    /// 写成计算属性而不是存一个字段，是为了从根上避免
    /// 「同一个会话有两个不同的 id」这种难查的 bug。
    var id: Friend.ID { friend.id }

    var friend: Friend
    var lastMessage: String
    var lastTime: Date
    var unreadCount: Int

    /// 是否已拉黑这个好友。
    ///
    /// 拉黑之后：会话在列表里会被标记、聊天页会显示一条提示、
    /// 并且**对方再发消息也不会进来**（见 ChatStore.receive）。
    ///
    /// 说明：现在的"拒收"是在本地生效的。接上真服务器之后，
    /// 服务器那边也会一起拦，这样换设备登录也依然是拉黑状态。
    var isBlocked: Bool

    init(
        friend: Friend,
        lastMessage: String,
        lastTime: Date,
        unreadCount: Int = 0,
        isBlocked: Bool = false
    ) {
        self.friend = friend
        self.lastMessage = lastMessage
        self.lastTime = lastTime
        self.unreadCount = unreadCount
        self.isBlocked = isBlocked
    }

    // 只按 id 判断是不是同一个会话。
    // 否则「最后一条消息变了」会被当成「换了一个会话」，
    // 界面上可能出现列表跳动、导航栈错乱之类的问题。
    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
