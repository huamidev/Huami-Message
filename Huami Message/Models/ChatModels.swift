import SwiftUI

// MARK: - 好友

/// 一个真实好友。
///
/// 注意这里存的是 avatarSeed（一个数字）而不是颜色。
/// 原因：以后好友信息要从服务器来，颜色是存不进数据库的，但数字可以。
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
    var sender: Sender
    var sentAt: Date

    /// 这条消息是不是经过 AI 润色的、用了哪种风格。
    ///
    /// 界面上会在气泡下面显示一个小标记，让用户清楚地知道
    /// 「这条不是我原话」。这是「用户知情」——
    /// 既是产品伦理，也是上架审核会看的东西。
    var polishedWith: PolishStyle?

    init(
        id: UUID = UUID(),
        friendID: Friend.ID,
        text: String,
        sender: Sender,
        sentAt: Date = .now,
        polishedWith: PolishStyle? = nil
    ) {
        self.id = id
        self.friendID = friendID
        self.text = text
        self.sender = sender
        self.sentAt = sentAt
        self.polishedWith = polishedWith
    }
}

// MARK: - 会话

/// 会话列表里的一行。
///
/// 它自己不存消息，只存「最后一条的摘要」。真正的消息在
/// ChatStore.messagesByFriend 里按好友分开存。
struct Conversation: Identifiable, Hashable {
    let id: UUID
    var friend: Friend
    var lastMessage: String
    var lastTime: Date
    var unreadCount: Int

    init(
        id: UUID = UUID(),
        friend: Friend,
        lastMessage: String,
        lastTime: Date,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.friend = friend
        self.lastMessage = lastMessage
        self.lastTime = lastTime
        self.unreadCount = unreadCount
    }
}
