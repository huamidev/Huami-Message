import Foundation
import SwiftData

// ============================================================================
// 本地数据库的「插座标准」
// ============================================================================
//
// 和 ChatService 是同一个思路：界面和 ChatStore 只跟这个协议说话，
// 不知道底下到底是 SwiftData、SQLite 还是别的什么。
//
// ⚠️ 特别注意：这里的方法**全是同步的，没有 async**。
// 这不是偷懒，是故意的、也是关键：
// **本地读取必须"立刻返回"，一秒都不能等。**
// 界面打开时读本地是同步的、几毫秒就回来了，所以用户感觉不到加载。
// 一旦写成 async，就会冒出"转圈圈"和"闪一下"，那就不是瞬间可用了。
//
// ============================================================================

protocol LocalStore: AnyObject {

    /// 当前登录的账号。设置它之后，读写都只针对这个账号的数据。
    var ownerIDString: String { get set }

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
    /// 这时候如果同步拿服务器上的旧数据往下盖，就会把本地刚写好的
    /// 「已发送」又覆盖回「发送中」—— 更糟的情况是直接把那条消息盖没了。
    ///
    /// 所以「服务器来的数据」必须有自己的一套合并规则：
    /// **本地还处于「发送中 / 发送失败」的消息，一律以本地为准，不许被覆盖。**
    ///
    /// 这类问题在真机上比模拟器严重得多：网络越慢，撞车的窗口越大。
    func saveFromRemote(_ message: Message)

    /// 批量存一批**从服务器来的**消息。
    ///
    /// 【为什么不循环调上面那个单条方法】
    /// 因为每次单条调用都会 `context.save()` 一次，也就是一个数据库事务。
    /// 首次同步几百条历史消息时，那就是几百个事务 —— 慢到用户能感觉到。
    /// 批量版本只落盘一次。
    func saveFromRemote(_ messages: [Message])

    /// 更新未读数
    func setUnread(_ count: Int, for friendID: Friend.ID)

    // MARK: 用户对自己数据的控制
    //
    // 这一组方法是 App Store 审核和用户信任的**共同要求**：
    // 用户必须能删掉自己的数据，也必须能把讨厌的人挡住。
    // 一个删不掉聊天记录的聊天 App，是过不了审核的。

    /// 删除一整个会话（连同里面的所有消息）
    func deleteConversation(friendID: Friend.ID)

    /// 把某个好友和它的消息从本地抹掉，**但不留墓碑**。
    ///
    /// 【为什么必须和 deleteConversation 分开】
    ///
    /// `deleteConversation` 是"**用户主动**删好友"，要留墓碑 ——
    /// 否则下次同步会把他又拉回来。
    ///
    /// 这个是"**服务器上已经没有他了**，本地跟着清"，绝对不能留墓碑：
    /// 留了的话，他以后再加你，就永远加不回来了 ——
    /// 墓碑会挡住所有"把他同步回来"的尝试，而且没有任何界面能撤销它。
    ///
    /// 一句话：**墓碑是"我不想再见到他"，不是"他在服务器上没了"。**
    func forgetFriend(friendID: Friend.ID)

    /// 清掉某个好友的"墓碑"。
    ///
    /// 【什么时候需要它 —— 一个真实的 bug】
    ///
    /// 用户删掉一个好友时，本地会记一笔"我不想再见到他"（墓碑），
    /// 作用是**挡住同步把他拉回来**。
    ///
    /// 但**"同意他的好友申请"本身就是一次新的同意** ——
    /// 墓碑必须清掉，否则会出现：他申请我、我点了同意、服务器上已经是好友了，
    /// 而我这边**列表里还是空的**（本地那一步被墓碑挡住）。
    ///
    /// 用户看到的就是"点了同意，和没加一样"。
    func clearTombstone(friendID: Friend.ID)

    /// 只清空聊天记录，保留好友
    func clearMessages(with friendID: Friend.ID)

    /// 删除单条消息
    func deleteMessage(id: Message.ID)

    /// 拉黑 / 取消拉黑
    func setBlocked(_ blocked: Bool, for friendID: Friend.ID)

    /// 记下一条举报
    func saveReport(_ report: Report)

    /// 读出某个好友的举报记录
    func reports(for friendID: Friend.ID) -> [Report]

    /// 删掉**全部**本地数据：好友、消息、举报记录、删除墓碑。
    /// 这是"注销账号"在本地那一半。
    func deleteEverything()
}

// ============================================================================
// SwiftData 版实现
// ============================================================================
//
// 换了它不会影响任何界面代码 —— 这就是协议的价值。
//
// 【这一版最重要的改动：查询下推到数据库】
//
// 之前的写法是"把整张表捞出来，再在内存里 filter"。
// 只有几十条消息时看不出问题，但它是个**平方级的坑**：
// 会话列表要对每个好友查一次最后一条消息，于是 N 个好友 × M 条消息
// = N×M 次比较。消息攒到几千条，打开 App 就会明显变慢。
//
// 现在全部改成 `#Predicate`（数据库层的查询条件）+ 按需 `fetchLimit`，
// 让数据库自己用索引去查。这才是"打开就有内容"能一直成立的前提。
//
// ============================================================================

final class SwiftDataLocalStore: LocalStore {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: 读

    /// 当前登录的是哪个账号。
    ///
    /// 界面在登录 / 退出时会设置它。本地库里每条数据都带着自己的归属，
    /// **只显示和当前账号对得上的那些** —— 这就是"账号之间互相看不见"。
    var ownerIDString: String = ""

    /// 只留下属于当前账号的记录。
    ///
    /// 在内存里过滤而不是写进数据库查询条件：本地数据量很小（几十个好友、
    /// 几千条消息），而这样写**只有一个地方需要维护** ——
    /// 用 `#Predicate` 的话，每个查询都得记得加一次，漏一个就是一个数据泄露。
    private func owned<T>(_ items: [T], _ owner: (T) -> String) -> [T] {
        items.filter { owner($0) == ownerIDString }
    }

    func loadConversations() -> [Conversation] {
        // 好友数量很少（几十个），全查没问题
        let friends = owned(fetchAll(StoredFriend.self)) { $0.ownerIDString }

        return friends
            .map { stored in
                let last = lastMessage(with: stored.id)
                return Conversation(
                    friend: stored.asFriend,
                    lastMessage: last?.preview ?? "",
                    lastTime: last?.sentAt ?? .distantPast,
                    unreadCount: stored.unreadCount,
                    isBlocked: stored.isBlocked
                )
            }
            // 最近说话的排最前面
            .sorted { $0.lastTime > $1.lastTime }
    }

    func loadMessages(with friendID: Friend.ID) -> [Message] {
        let descriptor = FetchDescriptor<StoredMessage>(
            predicate: #Predicate { $0.friendID == friendID },
            sortBy: [SortDescriptor(\.sentAt, order: .forward)]
        )
        return owned(fetch(descriptor)) { $0.ownerIDString }.map(\.asMessage)
    }

    // MARK: 写

    func save(friend: Friend) {
        // 已经被用户删掉的好友，不能被同步重新拉回来
        guard !deletedIDs().contains(friend.id) else { return }

        if let existing = findFriend(friend.id) {
            existing.apply(friend, ownerIDString: ownerIDString)
        } else {
            let stored = StoredFriend(id: friend.id, name: friend.name, avatarSeed: friend.avatarSeed)
            stored.apply(friend, ownerIDString: ownerIDString)
            context.insert(stored)
        }
        commit()
    }

    func save(_ message: Message) {
        apply(message, protectLocalPending: false, deleted: deletedIDs())
        commit()
    }

    func saveFromRemote(_ message: Message) {
        apply(message, protectLocalPending: true, deleted: deletedIDs())
        commit()
    }

    func saveFromRemote(_ messages: [Message]) {
        guard !messages.isEmpty else { return }

        // 一次把墓碑读出来，而不是每条消息都查一遍。
        let deleted = deletedIDs()

        // ── 关键优化：先把"已经存在的消息 id"一次查出来 ──
        //
        // 原来每条消息都要查一次数据库看它在不在（`findMessage`）。
        // 5000 条 = 5000 次查询，实测光这一项就要好几秒。
        //
        // 首次同步时绝大多数消息都是新的，所以只要预先知道"哪些已经存在"，
        // 剩下的全都不用查，直接插。
        let watchPreload = Stopwatch()
        var existingIDs = Set<UUID>()
        for friendID in Set(messages.map(\.friendID)) {
            // 注意 self.：参数名 messages 把同名方法遮住了
            existingIDs.formUnion(self.messages(of: friendID).map(\.id))
        }
        let preloadMs = watchPreload.milliseconds

        // ── 分批落盘 ──
        //
        // 一次提交 5005 条，实测主线程会卡住约 180 毫秒 —— 差不多是 11 帧。
        // 用户不一定能说出哪里卡，但滑起来就是"不顺"。
        // 拆成每 400 条提交一次，单次卡顿降到十几毫秒，滚动时基本感觉不出来。
        //
        // 中途失败也不会出问题：写入本身是幂等的（同 id 覆盖），
        // 下次同步会从断掉的地方继续。
        let chunkSize = 400

        let watchLoop = Stopwatch()
        var written = 0
        var lastCommitMs = 0.0
        var start = 0
        while start < messages.count {
            let end = min(start + chunkSize, messages.count)
            for message in messages[start..<end]
            where apply(message, protectLocalPending: true, deleted: deleted, knownExisting: existingIDs) {
                written += 1
            }
            let watchCommit = Stopwatch()
            commit()
            lastCommitMs = watchCommit.milliseconds
            start = end
        }
        let loopMs = watchLoop.milliseconds

        AppLog.info(.data,
            "批量写入 \(written)/\(messages.count) 条（分 \((messages.count + chunkSize - 1) / chunkSize) 批）"
            + "｜预读 \(Stopwatch.format(preloadMs))｜插入+落盘 \(Stopwatch.format(loopMs))"
            + "｜最后一批落盘 \(Stopwatch.format(lastCommitMs))")
    }

    /// 合并一条消息。**这个方法不落盘**，由调用方决定什么时候 commit。
    ///
    /// - Returns: 真的写进去了才返回 true（被墓碑挡住、或被本地待发状态保护而跳过的返回 false）
    /// - Parameter knownExisting:
    ///   批量写入时预先查好的"已经存在的消息 id"。
    ///   传了它就不再逐条查数据库；不传（单条写入）就自己查。
    @discardableResult
    private func apply(_ message: Message,
                       protectLocalPending: Bool,
                       deleted: Set<UUID>,
                       knownExisting: Set<UUID>? = nil) -> Bool {
        // ① 这条消息本身被删过 / 它所属的好友被删过 —— 都不能再进来。
        //    没有这两行，用户删掉的会话会被后台同步"复活"（我踩过）。
        guard !deleted.contains(message.id), !deleted.contains(message.friendID) else { return false }

        // 已知不存在，就不必白查一次数据库
        if knownExisting?.contains(message.id) == false {
            let stored = StoredMessage(from: message)
            stored.ownerIDString = ownerIDString
            context.insert(stored)
            return true
        }

        if let existing = findMessage(message.id) {
            if protectLocalPending,
               let localStatus = MessageStatus(rawValue: existing.statusRaw),
               localStatus == .sending || localStatus == .failed {
                // 本地还没定论，服务器的旧版本不代表最终结果 —— 直接跳过。
                return false
            }
            // ⚠️ **这里是一个很容易漏的坑：字段要一个一个抄。**
            //
            // 我加图片功能时就漏了 imageURLString ——
            // 现象是"图片发出去了、服务器也收到了，但界面显示成一条空消息"。
            // 因为插入的时候是全量拷贝（StoredMessage(from:)），
            // 而更新的时候是手写字段，**加了新字段很容易只改一处**。
            //
            // 以后再加消息字段，**两个地方都要改**（这里和 StoredMessage 的 init）。
            existing.ownerIDString = ownerIDString
            existing.apply(message)
            // statusRaw **单独设**：它是本地说了算的，
            // 不属于"从消息本身覆盖"的那一组（见 apply 的说明）
            existing.statusRaw = message.status.rawValue
        } else {
            let stored = StoredMessage(from: message)
            stored.ownerIDString = ownerIDString
            context.insert(stored)
        }
        return true
    }

    func setUnread(_ count: Int, for friendID: Friend.ID) {
        guard let friend = findFriend(friendID) else { return }
        friend.unreadCount = count
        commit()
    }

    // MARK: 删除与拉黑

    func clearTombstone(friendID: Friend.ID) {
        for tombstone in fetchAll(StoredTombstone.self)
        where tombstone.targetID == friendID {
            context.delete(tombstone)
        }
        commit()
    }

    func forgetFriend(friendID: Friend.ID) {
        // 和 deleteConversation 同样的删除顺序（先消息后好友），
        // **唯一的区别是不写墓碑**。理由见协议那边的说明。
        for message in messages(of: friendID) {
            context.delete(message)
        }
        if let friend = findFriend(friendID) {
            context.delete(friend)
        }
        commit()
    }

    func deleteConversation(friendID: Friend.ID) {
        // 先删消息，再删好友 —— 顺序不能反。
        // 反过来的话，删掉好友之后就找不到"哪些消息属于他"了，
        // 会在数据库里留下永远删不掉的垃圾数据。
        for message in messages(of: friendID) {
            context.delete(message)
            addTombstone(message.id, kind: "message")
        }
        if let friend = findFriend(friendID) {
            context.delete(friend)
            addTombstone(friendID, kind: "friend")   // ← 最关键：挡住同步把它拉回来
        }
        // 注意：举报记录**故意保留**。
        // 它是"发生过什么"的凭证，不该因为用户删了会话就一起消失。
        commit()
    }

    func clearMessages(with friendID: Friend.ID) {
        for message in messages(of: friendID) {
            context.delete(message)
            addTombstone(message.id, kind: "message")
        }
        // 聊天记录都清了，"未读"也就没有意义了
        if let friend = findFriend(friendID) {
            friend.unreadCount = 0
        }
        commit()
    }

    func deleteMessage(id: Message.ID) {
        if let message = findMessage(id) {
            context.delete(message)
            addTombstone(id, kind: "message")
        }
        commit()
    }

    func setBlocked(_ blocked: Bool, for friendID: Friend.ID) {
        guard let friend = findFriend(friendID) else { return }
        friend.isBlocked = blocked
        commit()
    }

    func saveReport(_ report: Report) {
        context.insert(StoredReport(from: report))
        commit()
    }

    func reports(for friendID: Friend.ID) -> [Report] {
        let descriptor = FetchDescriptor<StoredReport>(
            predicate: #Predicate { $0.friendID == friendID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return fetch(descriptor).map(\.asReport)
    }

    func deleteEverything() {
        // 四张表一张都不留。
        // 注意**墓碑也要删** —— 如果留着墓碑，用户之后重新加同一个好友时，
        // 那些"这个 id 被删过"的记录会把新数据挡在门外，变成一桩查不出来的怪事。
        deleteAll(StoredMessage.self)
        deleteAll(StoredFriend.self)
        deleteAll(StoredReport.self)
        deleteAll(StoredTombstone.self)
        commit()
    }

    // MARK: 内部 —— 查询

    /// 一次查询就够的通用入口
    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.error(.data, "查询失败：\(String(describing: error))")
            return []
        }
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        fetch(FetchDescriptor<T>())
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        for item in fetchAll(type) { context.delete(item) }
    }

    private func findFriend(_ id: Friend.ID) -> StoredFriend? {
        var descriptor = FetchDescriptor<StoredFriend>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1          // 只要一条，别把整张表读上来
        return fetch(descriptor).first
    }

    private func findMessage(_ id: Message.ID) -> StoredMessage? {
        var descriptor = FetchDescriptor<StoredMessage>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func messages(of friendID: Friend.ID) -> [StoredMessage] {
        fetch(FetchDescriptor<StoredMessage>(predicate: #Predicate { $0.friendID == friendID }))
    }

    /// 某个好友最后一条消息。
    /// **按时间倒序取第一条**，而不是"全读出来再找最大的那个" ——
    /// 这个方法是会话列表每个好友都要调一次的，它的快慢直接决定打开 App 的快慢。
    private func lastMessage(with friendID: Friend.ID) -> Message? {
        var descriptor = FetchDescriptor<StoredMessage>(
            predicate: #Predicate { $0.friendID == friendID },
            sortBy: [SortDescriptor(\.sentAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first?.asMessage
    }

    /// 一次读出所有墓碑 id。
    /// 墓碑数量很少（用户删过的东西），整张表读出来完全没问题，
    /// 而且这样批量写入时就不用每条消息查一次了。
    private func deletedIDs() -> Set<UUID> {
        Set(fetchAll(StoredTombstone.self).map(\.targetID))
    }

    // MARK: 内部 —— 写入

    /// 真正落盘。
    ///
    /// 出错时只记录、不抛出去，是刻意的取舍：
    /// 存不进数据库（比如磁盘满了）不应该让 App 崩掉。
    /// 界面上的数据还在内存里，用户还能继续用，只是这次没存下来。
    private func commit() {
        do {
            try context.save()
        } catch {
            AppLog.error(.data, "写入失败：\(String(describing: error))")
        }
    }

    /// 记下"这个 id 被删了"。
    /// 已经记过就不重复记 —— 墓碑表不该因为用户反复删同一件事而膨胀。
    private func addTombstone(_ id: UUID, kind: String) {
        guard !deletedIDs().contains(id) else { return }
        context.insert(StoredTombstone(targetID: id, kindRaw: kind))
    }
}
