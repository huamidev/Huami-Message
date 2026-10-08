import Foundation
import SwiftData

/// 本地数据库的「插座标准」。
///
/// 和 ChatService 是同一个思路：界面和 ChatStore 只跟这个协议说话，
/// 不知道底下到底是 SwiftData、SQLite 还是别的什么。
///
/// ⚠️ 特别注意：这里的方法**全是同步的，没有 async**。
/// 这不是我偷懒，是故意的、也是关键：
/// **本地读取必须"立刻返回"，一秒都不能等。**
/// 界面打开时读本地是同步的、几毫秒就回来了，所以用户感觉不到加载。
/// 一旦写成 async，就会冒出"转圈圈"和"闪一下"，那就不是瞬间可用了。
protocol LocalStore {

    /// 读出所有会话，按最近说话时间从新到旧。
    /// 界面启动时第一件事就是调它 —— 这个调用有多快，决定 App 打开有多快。
    func loadConversations() -> [Conversation]

    /// 读出和某个好友的全部消息，按时间从早到晚
    func loadMessages(with friendID: Friend.ID) -> [Message]

    /// 存好友。已经存在就更新，不会存出两份。
    func save(friend: Friend)

    /// 存消息。同一个 id 就覆盖（覆盖是实现「发送中 → 已发送」的关键）。
    func save(_ message: Message)

    /// 存一条**从服务器来的**消息。
    ///
    /// 【为什么它和 save 要分开？这是一个真实的 bug 换来的教训】
    ///
    /// 本地优先架构有个必然的副作用：界面在"读本地"那一步就已经可用了，
    /// 而"后台同步"还在跑。用户完全可能在同步还没结束时就发出一条消息。
    ///
    /// 这时候如果同步傻乎乎地拿服务器上的旧数据往下盖，就会把本地刚写好的
    /// 「已发送」又覆盖回「发送中」—— 更糟的情况是直接把那条消息盖没了。
    ///
    /// 所以「服务器来的数据」必须有自己的一套合并规则：
    /// **本地还处于「发送中 / 发送失败」的消息，一律以本地为准，不许被覆盖。**
    ///
    /// 这类问题在真机上比模拟器严重得多：网络越慢，撞车的窗口越大。
    func saveFromRemote(_ message: Message)

    /// 更新未读数
    func setUnread(_ count: Int, for friendID: Friend.ID)
}

// MARK: - SwiftData 版实现

/// 真家伙：把数据写进手机上的一个数据库文件。
///
/// 换了它不会影响任何界面代码 —— 这就是协议的价值。
final class SwiftDataLocalStore: LocalStore {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: 读

    func loadConversations() -> [Conversation] {
        let friends = fetchAll(StoredFriend.self)

        return friends
            .map { stored in
                let last = lastMessage(with: stored.id)
                return Conversation(
                    friend: stored.asFriend,
                    lastMessage: last?.text ?? "",
                    lastTime: last?.sentAt ?? .distantPast,
                    unreadCount: stored.unreadCount
                )
            }
            // 最近说话的排最前面
            .sorted { $0.lastTime > $1.lastTime }
    }

    func loadMessages(with friendID: Friend.ID) -> [Message] {
        // 说明：这里是把消息全捞出来再在内存里筛。
        //
        // 为什么不用数据库的查询条件（predicate）直接筛？因为更稳。
        // 消息量大到几万条时确实要改成 predicate，那是个明确的优化点，
        // 我会在真的需要时才做 —— 现在做只会增加出错的机会。
        fetchAll(StoredMessage.self)
            .filter { $0.friendID == friendID }
            .sorted { $0.sentAt < $1.sentAt }
            .map(\.asMessage)
    }

    // MARK: 写

    func save(friend: Friend) {
        // 先找有没有同一个好友：有就更新，没有才新建。
        // 这个动作习惯上叫 "upsert"。
        if let existing = fetchAll(StoredFriend.self).first(where: { $0.id == friend.id }) {
            existing.name = friend.name
            existing.avatarSeed = friend.avatarSeed
        } else {
            context.insert(StoredFriend(id: friend.id, name: friend.name, avatarSeed: friend.avatarSeed))
        }
        commit()
    }

    func save(_ message: Message) {
        merge(message, protectingLocalPending: false)
    }

    func saveFromRemote(_ message: Message) {
        merge(message, protectingLocalPending: true)
    }

    /// 存消息的实际逻辑。
    ///
    /// - Parameter protectingLocalPending:
    ///   true 表示这条数据来自服务器，遇到"本地还在发送中/发送失败"的消息要让路。
    private func merge(_ message: Message, protectingLocalPending: Bool) {
        if let existing = fetchAll(StoredMessage.self).first(where: { $0.id == message.id }) {

            if protectingLocalPending,
               let localStatus = MessageStatus(rawValue: existing.statusRaw),
               localStatus == .sending || localStatus == .failed {
                // 本地还没定论，服务器的旧版本不代表最终结果 —— 直接跳过。
                return
            }

            existing.text = message.text
            existing.sentAt = message.sentAt
            existing.polishedStyle = message.polishedWith?.rawValue
            existing.statusRaw = message.status.rawValue
        } else {
            context.insert(StoredMessage(from: message))
        }
        commit()
    }

    func setUnread(_ count: Int, for friendID: Friend.ID) {
        guard let friend = fetchAll(StoredFriend.self).first(where: { $0.id == friendID }) else { return }
        friend.unreadCount = count
        commit()
    }

    // MARK: 内部

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// 真正落盘。
    ///
    /// 出错时只打印、不抛出去，是刻意的取舍：
    /// 存不进数据库（比如磁盘满了）不应该让 App 崩掉。
    /// 界面上的数据还在内存里，用户还能继续用，只是这次没存下来。
    private func commit() {
        do {
            try context.save()
        } catch {
            print("⚠️ 本地数据库写入失败：", error)
        }
    }

    private func lastMessage(with friendID: Friend.ID) -> Message? {
        fetchAll(StoredMessage.self)
            .filter { $0.friendID == friendID }
            .max { $0.sentAt < $1.sentAt }?
            .asMessage
    }
}
