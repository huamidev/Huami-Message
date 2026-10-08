import Foundation
import SwiftData

/// 本地数据库里的「好友」。
///
/// ⚠️ 先理解一件事：这个文件里的 @Model 类，和 Models/ChatModels.swift 里的
/// Friend / Message 是**两套东西**：
///
///   · ChatModels 里的 struct —— 界面用的、在代码里传来传去的「数据包」
///   · 这里的 @Model class —— 真正躺在数据库文件里的「档案」
///
/// 为什么要费事分两套？因为数据库的写法（表结构、字段、索引）是会变的，
/// 而界面不该关心这些。分开了以后，改数据库结构不用动界面一行代码。
///
/// 这跟 ChatService 那道「插座防火墙」是同一个思路：
/// **每一层只跟自己那一层的邻居打交道。**
@Model
final class StoredFriend {

    var id: UUID
    var name: String
    var avatarSeed: Int

    /// 未读消息数。
    ///
    /// 严格说「未读」属于「会话」而不是「好友」，但第一版只有一对一，
    /// 一个人就对应一个会话，所以放在这里最简单。
    /// 以后做群聊时，这里要拆出一张独立的「会话」表。
    var unreadCount: Int

    init(id: UUID, name: String, avatarSeed: Int, unreadCount: Int = 0) {
        self.id = id
        self.name = name
        self.avatarSeed = avatarSeed
        self.unreadCount = unreadCount
    }

    /// 转成界面用的 struct
    var asFriend: Friend {
        Friend(id: id, name: name, avatarSeed: avatarSeed)
    }
}

/// 本地数据库里的「消息」。
@Model
final class StoredMessage {

    var id: UUID
    var friendID: UUID
    var text: String

    /// 是不是我发的。
    /// 数据库里存 Bool 而不是存 enum，是为了简单可靠 —— 只有两种情况。
    var isMine: Bool

    var sentAt: Date

    /// 用了哪种润色风格。
    ///
    /// 这里刻意存 String（原始值）而不是直接存 enum：
    /// 数据库字段用最朴素的类型，以后 enum 加了新情况也不会让旧数据读不出来。
    /// 这是"数据库里存简单类型"这条通用经验的体现。
    var polishedStyle: String?

    /// 发送状态，同样存 String
    var statusRaw: String

    init(
        id: UUID,
        friendID: UUID,
        text: String,
        isMine: Bool,
        sentAt: Date,
        polishedStyle: String?,
        statusRaw: String
    ) {
        self.id = id
        self.friendID = friendID
        self.text = text
        self.isMine = isMine
        self.sentAt = sentAt
        self.polishedStyle = polishedStyle
        self.statusRaw = statusRaw
    }

    /// 从界面用的 struct 造一条档案
    convenience init(from message: Message) {
        self.init(
            id: message.id,
            friendID: message.friendID,
            text: message.text,
            isMine: message.sender == .me,
            sentAt: message.sentAt,
            polishedStyle: message.polishedWith?.rawValue,
            statusRaw: message.status.rawValue
        )
    }

    /// 转成界面用的 struct
    var asMessage: Message {
        Message(
            id: id,
            friendID: friendID,
            text: text,
            sender: isMine ? .me : .friend,
            sentAt: sentAt,
            polishedWith: polishedStyle.flatMap(PolishStyle.init(rawValue:)),
            status: MessageStatus(rawValue: statusRaw) ?? .sent
        )
    }
}
