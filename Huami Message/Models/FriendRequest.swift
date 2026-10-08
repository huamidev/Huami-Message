import Foundation

/// 一条好友申请。
///
/// 附带上申请人的资料（昵称、用户名、头像）—— 因为界面上要显示
/// "谁想加你"，只给一个 id 是没用的。
struct FriendRequest: Identifiable, Hashable {

    let id: UUID

    /// 申请人
    let fromID: UUID
    let fromName: String
    let fromUsername: String
    let fromAvatarURL: URL?

    /// 附言。可以没有。
    let note: String?

    let createdAt: Date
}

/// 搜到一个人之后、还没加之前，给他看的那个"主页卡片"。
///
/// 和 `Friend` 分开：`Friend` 是"已经是好友的人"，
/// 而这个可能只是一面之缘 —— 加不加得成还不一定。
struct ProfileSummary: Identifiable, Hashable {

    let id: UUID
    let displayName: String
    let username: String
    let avatarSeed: Int
    let avatarURL: URL?

    /// 头像上显示的那个字
    var initial: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}
