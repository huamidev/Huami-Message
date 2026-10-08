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

    /// **这条数据属于哪个账号**（账号的用户 ID 字符串）。
    ///
    /// 【为什么必须要有这个字段 —— 这是一个真实且严重的 bug】
    ///
    /// 本地数据库原来**没有任何"归属"概念**：谁登录过，数据就都混在一起。
    /// 用户拿两个账号在这台手机上登过，结果：
    ///
    ///   消息列表里同时出现两个账号的会话，
    ///   而且**两条都叫「我」**（注册时给的默认昵称），
    ///   于是看起来像"昵称没更新" —— 其实是**看到了另一个账号的数据**。
    ///
    /// 这不只是显示问题：**A 账号能看到 B 账号的聊天记录**，
    /// 是隐私事故。
    ///
    /// 存字符串而不是 UUID：SwiftData 的 `#Predicate` 对可选值和 UUID
    /// 的比较有些坑，而字符串比较永远可靠。空字符串表示"还没归属"
    ///（旧数据就是这种状态，加上这个字段之后它们自然不再显示）。
    var ownerIDString: String = ""

    var name: String
    var avatarSeed: Int

    /// 未读消息数。
    ///
    /// 严格说「未读」属于「会话」而不是「好友」，但第一版只有一对一，
    /// 一个人就对应一个会话，所以放在这里最简单。
    /// 以后做群聊时，这里要拆出一张独立的「会话」表。
    var unreadCount: Int

    /// 是否已拉黑。
    ///
    /// 注意这里给了默认值 `= false`：给新字段加默认值，
    /// 数据库在升级结构时可以自动迁移旧数据（旧记录一律当作"没拉黑"），
    /// 不会因为"多了一个字段"就把老数据全读不出来。
    /// **这是加数据库字段时的一个好习惯：永远给它一个合理的默认值。**
    var isBlocked: Bool = false

    init(id: UUID, name: String, avatarSeed: Int, unreadCount: Int = 0, isBlocked: Bool = false) {
        self.id = id
        self.name = name
        self.avatarSeed = avatarSeed
        self.unreadCount = unreadCount
        self.isBlocked = isBlocked
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

    /// 这条消息属于哪个账号。理由见 `StoredFriend.ownerIDString`。
    var ownerIDString: String = ""

    var friendID: UUID
    var text: String

    /// 图片地址。
    ///
    /// 存字符串而不是 URL：SwiftData 对 URL 的处理不如字符串稳，
    /// 而且"空值""格式不对"这种情况，用字符串判断直白得多。
    var imageURLString: String?

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
        imageURLString: String?,
        isMine: Bool,
        sentAt: Date,
        polishedStyle: String?,
        statusRaw: String
    ) {
        self.id = id
        self.friendID = friendID
        self.text = text
        self.imageURLString = imageURLString
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
            imageURLString: message.imageURL?.absoluteString,
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
            imageURL: imageURLString.flatMap(URL.init(string:)),
            sender: isMine ? .me : .friend,
            sentAt: sentAt,
            polishedWith: polishedStyle.flatMap(PolishStyle.init(rawValue:)),
            status: MessageStatus(rawValue: statusRaw) ?? .sent
        )
    }
}

/// 本地数据库里的「举报记录」。
///
/// 举报必须**留痕**：审核要看的不只是"有个举报按钮"，
/// 还要能说明举报之后会发生什么。存下来是最基本的。
/// 接上服务器之后，这里会多一个"是否已上报"的状态。
@Model
final class StoredReport {

    var id: UUID
    var friendID: UUID
    var reasonRaw: String
    var note: String
    var createdAt: Date

    init(id: UUID, friendID: UUID, reasonRaw: String, note: String, createdAt: Date) {
        self.id = id
        self.friendID = friendID
        self.reasonRaw = reasonRaw
        self.note = note
        self.createdAt = createdAt
    }

    convenience init(from report: Report) {
        self.init(
            id: report.id,
            friendID: report.friendID,
            reasonRaw: report.reason.rawValue,
            note: report.note,
            createdAt: report.createdAt
        )
    }

    var asReport: Report {
        Report(
            id: id,
            friendID: friendID,
            reason: ReportReason(rawValue: reasonRaw) ?? .other,
            note: note,
            createdAt: createdAt
        )
    }
}

/// 删除墓碑。
///
/// 【为什么删掉的东西还要留一条"我删过它"的记录？】
///
/// 这是一个真实的 bug 换来的，而且是本地优先架构里最经典的一类坑：
///
/// 用户删掉一个会话 → 后台同步一跑 → **又从服务器把它拉回来了**。
/// 因为同步根本分不清这两种情况：
///     · "这台设备从没见过它"      → 应该拉下来
///     · "用户故意删了它"          → 绝不能拉回来
///
/// 解决办法就是**留一条墓碑**：删除不是"抹掉"，而是"记下它被删过"。
/// 同步时看到墓碑就跳过。
///
/// 接上 Supabase 之后，墓碑还要多一个作用：
/// **把"我删了它"这件事同步到服务器**，否则换台设备登录，删掉的东西又回来了。
/// （到那时候，等服务器确认删除之后，墓碑才可以清掉 —— 不然会越积越多。）
@Model
final class StoredTombstone {

    /// 被删除对象的 id（好友的 id 或消息的 id）
    var targetID: UUID

    /// 删的是什么："friend" 或 "message"
    var kindRaw: String

    var deletedAt: Date

    init(targetID: UUID, kindRaw: String, deletedAt: Date = .now) {
        self.targetID = targetID
        self.kindRaw = kindRaw
        self.deletedAt = deletedAt
    }
}
