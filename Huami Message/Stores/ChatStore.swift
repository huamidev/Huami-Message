import SwiftUI

/// 消息模块的「总管家」。
///
/// 界面只做两件事：读它里面的数据、调它的方法。
/// 界面完全不关心数据是本地数据库来的还是服务器来的。
///
/// 【它现在管着两个"下属"，这是整个 App 最关键的架构】
///
///     ChatStore
///      ├── local  （本地数据库）  ← 界面读它。同步、几毫秒、不等网络
///      └── remote （服务器）      ← 只在后台往里补，界面不直接读它
///
/// 这就是「打开 App 瞬间就能操作」的全部秘密：
/// **界面永远只等本地，永远不等网络。**
/// 网络快就快一点补上，网络慢或者断了，界面照样能用。
///
/// @Observable 是苹果现在的标准写法：数据一变，用到它的界面自动刷新。
@Observable
final class ChatStore {

    // MARK: - 界面要读的数据

    private(set) var conversations: [Conversation] = []

    /// 每个好友对应的消息列表。
    /// 用字典按好友分开存，切换会话时不用重新查数据库，进出都是瞬间的。
    private(set) var messagesByFriend: [Friend.ID: [Message]] = [:]

    /// 是不是**第一次**加载（本地数据库是空的）。
    /// 注意：只有第一次装 App 才会是 true。
    /// 之后每次打开，本地已经有数据了，这个值立刻就是 false —— 界面直接出内容，不转圈。
    private(set) var isLoading = false

    // MARK: - 两个下属

    private let local: LocalStore
    private let remote: ChatService

    private var listenTask: Task<Void, Never>?

    init(local: LocalStore, remote: ChatService = MockChatService()) {
        self.local = local
        self.remote = remote
    }

    // MARK: - 读

    /// 取某个好友的消息（界面用）
    func messages(with friendID: Friend.ID) -> [Message] {
        messagesByFriend[friendID] ?? []
    }

    // MARK: - 启动

    /// App 启动时调一次。
    ///
    /// 请仔细看这个方法的**顺序** —— 它就是「丝滑」这两个字的实现：
    ///
    ///   ① 先把本地的东西同步读出来（几毫秒），界面立刻有内容
    ///   ② 再去后台悄悄同步服务器（可能要几秒），拉到什么补什么
    ///
    /// 顺序反过来的话（先等网络），App 打开就会转圈 —— 那是所有"卡顿感"的来源。
    func start() async {
        guard conversations.isEmpty else { return }

        // ── ① 本地优先 ──
        let localConversations = local.loadConversations()

        if localConversations.isEmpty {
            // 本地是空的 —— 说明是第一次装 App，或者刚被清过数据。
            // 只有这种情况下才需要让用户看到"加载中"。
            isLoading = true
        } else {
            // 本地有数据：立刻铺满界面。用户这一刻就可以开始操作了。
            conversations = localConversations
            for convo in localConversations {
                messagesByFriend[convo.friend.id] = local.loadMessages(with: convo.friend.id)
            }
        }

        // ── ② 后台同步 ──
        // 注意：界面不会等这一步。它已经在上面那一步变得可用了。
        if !DevFlags.offline {
            await syncFromRemote()
        }

        isLoading = false

        // ── ③ 开始监听服务器推来的新消息 ──
        if !DevFlags.offline {
            listen()
        }
    }

    /// 从服务器拉最新的数据，补进本地。
    ///
    /// 失败**不抛出去、不影响界面**，只打一行日志。
    /// 这是"网络差也不能让 App 变难用"的具体做法。
    private func syncFromRemote() async {
        do {
            let remoteConversations = try await remote.loadConversations()

            for convo in remoteConversations {
                local.save(friend: convo.friend)

                let remoteMessages = try await remote.loadMessages(with: convo.friend.id)
                for message in remoteMessages {
                    // 注意用 saveFromRemote 而不是 save：
                    // 它会跳过"本地还在发送中/发送失败"的消息，
                    // 避免后台同步把用户刚发的消息状态冲掉。
                    local.saveFromRemote(message)
                }
            }

            // 同步完了，重新从本地读一遍铺到界面上。
            // 注意这里读的还是**本地**，不是直接用服务器的返回值 ——
            // 这样"界面上显示的"和"数据库里存的"永远一致，不会出现对不上的情况。
            refreshFromLocal()
        } catch {
            print("后台同步失败（界面不受影响）：", error)
        }
    }

    /// 把界面上的数据整个换成本地数据库里的最新版本
    private func refreshFromLocal() {
        conversations = local.loadConversations()
        for convo in conversations {
            messagesByFriend[convo.friend.id] = local.loadMessages(with: convo.friend.id)
        }
    }

    // MARK: - 发送

    func send(_ text: String, to friendID: Friend.ID, polishedWith: PolishStyle? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // ① 先在本地造一条消息并立刻显示，状态是"发送中"。
        //    用户按下发送键的**那一瞬间**就看到它出现在列表里 —— 这一步完全不等网络。
        //    这就是 "绝不阻塞界面" 的具体做法，也是 Telegram 那种手感的真正来源：
        //    不是动画快，而是**从来不花时间等服务器**。
        let message = Message(
            friendID: friendID,
            text: trimmed,
            sender: .me,
            polishedWith: polishedWith,
            status: .sending
        )
        persist(message)
        messagesByFriend[friendID, default: []].append(message)
        touch(friendID: friendID, last: trimmed, at: message.sentAt)

        // ② 真正送出去
        await deliver(message)
    }

    /// 用户在界面上点了"重试"
    func retry(_ message: Message) async {
        var retrying = message
        retrying.status = .sending

        persist(retrying)
        replace(message.id, in: message.friendID, with: retrying)

        await deliver(retrying)
    }

    /// 把一条消息真正送出去，并根据结果更新它的状态。
    private func deliver(_ message: Message) async {
        do {
            let confirmed = try await remote.send(message)

            // ⚠️ 这里踩过一个坑，记下来：
            // 我原来直接存服务器返回的 confirmed，结果状态一直是"发送中" ——
            // 因为假服务是把消息原样返回的，里面带的还是 .sending。
            //
            // 正确的想法是：**能走到这一行，就已经说明服务器收到了**，
            // "没有抛错"本身就是确认。所以状态由我们这边拍板，不依赖服务器返回什么字段。
            // 这样即使以后换了后端、对方返回的字段不一样，这里也不会坏。
            var delivered = confirmed
            delivered.status = .sent

            persist(delivered)
            replace(message.id, in: message.friendID, with: delivered)
        } catch {
            // 失败了也不能"假装成功"。标记成失败，界面上会出现一个可以点的重试按钮。
            var failed = message
            failed.status = .failed
            persist(failed)
            replace(message.id, in: message.friendID, with: failed)
            print("发送失败：", error)
        }
    }

    // MARK: - 未读

    /// 进入某个会话时清掉未读小红点
    func markRead(_ friendID: Friend.ID) {
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }
        conversations[index].unreadCount = 0
        local.setUnread(0, for: friendID)   // 一起写进数据库，重启后不会又冒出来
    }

    // MARK: - 收消息

    /// 监听服务器推来的新消息。
    /// 这是「对方发消息给我，界面自动冒出来」的实现。
    private func listen() {
        guard listenTask == nil else { return }
        let remote = self.remote
        listenTask = Task { [weak self] in
            for await message in remote.incomingMessages() {
                self?.receive(message)
            }
        }
    }

    private func receive(_ message: Message) {
        // 去重：同一条消息只存一次（网络偶尔会重复推送，这是必须防的）
        let existing = messagesByFriend[message.friendID] ?? []
        guard !existing.contains(where: { $0.id == message.id }) else { return }

        persist(message)
        messagesByFriend[message.friendID, default: []].append(message)
        touch(friendID: message.friendID, last: message.text, at: message.sentAt, increaseUnread: true)
    }

    // MARK: - 辅助

    /// 存进本地数据库。
    /// 把"写数据库"收成一个小方法，是为了以后要加逻辑（比如加密、打日志）时只改一处。
    private func persist(_ message: Message) {
        local.save(message)
    }

    /// 替换掉本地那条消息（发送中 → 已发送 / 发送失败）
    private func replace(_ id: Message.ID, in friendID: Friend.ID, with message: Message) {
        guard let index = messagesByFriend[friendID]?.firstIndex(where: { $0.id == id }) else { return }
        messagesByFriend[friendID]?[index] = message
    }

    /// 更新会话列表里那一行的摘要、时间、未读数，并把它顶到最前面
    private func touch(friendID: Friend.ID, last: String, at date: Date, increaseUnread: Bool = false) {
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }

        conversations[index].lastMessage = last
        conversations[index].lastTime = date
        if increaseUnread {
            conversations[index].unreadCount += 1
            local.setUnread(conversations[index].unreadCount, for: friendID)
        }

        // 最近说话的会话排到第一位 —— 聊天 App 的基本预期
        let convo = conversations.remove(at: index)
        conversations.insert(convo, at: 0)
    }
}
