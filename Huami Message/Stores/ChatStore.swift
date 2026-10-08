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
///
/// 【为什么必须标 @MainActor】
///
/// 这是一个我查了很久的 bug 换来的：
///
/// **别人的昵称改了，界面永远不更新**（但数据库里其实是新名字）。
///
/// 原因：`@Observable` 只保证"属性变了会通知界面"，
/// **但通知是从哪个线程发出来的，它管不着**。而 Swift 里
/// `nonisolated` 的 async 方法被调用时**会跑到后台线程执行** ——
/// 于是 `conversations = ...` 发生在后台，通知也发在后台，
/// **SwiftUI 收到后不敢动界面**（它只在主线程更新）。
///
/// 表现极具迷惑性：**数据是对的，界面是旧的**。
/// 查数据库会以为没问题，因为确实没问题 —— 错的是"通知"这一步。
///
/// 标上 @MainActor 之后，这个类里所有方法都在主线程跑，
/// 这类问题从这里绝迹。所有给界面用的 store 都该这么写。
@MainActor
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

    init(local: LocalStore, remote: ChatService = AppServices.makeChatService()) {
        self.local = local
        self.remote = remote
    }

    /// 当前用的是不是假数据（界面据此显示「演示数据」标识）
    var isDemoData: Bool { remote.isDemoData }

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
        //
        // 这一段的速度就是"打开 App 有多快"。所以给它计时 ——
        // 以后消息攒到几千条时，这行日志能告诉你有没有变慢。
        let watch = Stopwatch()
        let localConversations = local.loadConversations()

        if localConversations.isEmpty {
            // 本地是空的 —— 说明是第一次装 App，或者刚被清过数据。
            // 只有这种情况下才需要让用户看到"加载中"。
            isLoading = true
        } else {
            // 本地有数据：立刻铺满界面。用户这一刻就可以开始操作了。
            conversations = localConversations
            var messageCount = 0
            for convo in localConversations {
                let list = local.loadMessages(with: convo.friend.id)
                messagesByFriend[convo.friend.id] = list
                messageCount += list.count
            }
            AppLog.info(.data,
                "本地读取：\(localConversations.count) 个会话 / \(messageCount) 条消息，耗时 \(Stopwatch.format(watch.milliseconds))")
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

    /// 只刷新「好友资料」——昵称、头像色，不碰消息。
    ///
    /// 【为什么需要单独一个轻量刷新】
    ///
    /// 原来的同步只在 `start()` 里跑，而 `start()` 有一句
    /// `guard conversations.isEmpty` —— 会话一旦读出来，就再也不会同步了。
    ///
    /// 后果：**别人改了昵称，你永远看不到**，除非杀掉 App 重开。
    /// （用户就是这么报的："现在自己改的昵称，根本不在别人那里显示"。）
    ///
    /// 但也不能直接重跑完整的 `syncFromRemote()` ——
    /// 那会为**每个好友**发一次"拉全部历史消息"的请求，
    /// 好友一多，每次切回前台都要打十几个请求。
    ///
    /// 所以拆出这个：只查一次好友列表（里面已经带着各自的昵称和头像色），
    /// 两个请求搞定，随时调都不心疼。
    func refreshFriends() async {
        guard !DevFlags.offline else { return }
        do {
            let remoteConversations = try await remote.loadConversations()
            guard !remoteConversations.isEmpty else { return }

            for convo in remoteConversations {
                local.save(friend: convo.friend)
            }
            refreshFromLocal()
            AppLog.info(.data, "好友资料已刷新（\(remoteConversations.count) 位）")
        } catch {
            // 刷新失败**不打扰用户** —— 他只是切了个前台，
            // 弹一个"刷新失败"比不刷新还烦。名字旧一点没关系。
            // （没登录时这里也会失败，正好一并挡掉。）
            AppLog.error(.network, "刷新好友资料失败：\(error.localizedDescription)")
        }
    }

    /// 从服务器拉最新的数据，补进本地。
    ///
    /// 失败**不抛出去、不影响界面**，只打一行日志。
    /// 这是"网络差也不能让 App 变难用"的具体做法。
    private func syncFromRemote() async {
        let watch = Stopwatch()
        do {
            let remoteConversations = try await remote.loadConversations()

            for convo in remoteConversations {
                local.save(friend: convo.friend)

                let remoteMessages = try await remote.loadMessages(with: convo.friend.id)
                // 注意用批量版本：一次落盘，而不是每条一个事务。
                // 首次同步几百条历史时，这个差别是"能感觉到"和"感觉不到"的差别。
                local.saveFromRemote(remoteMessages)
            }

            // 同步完了，重新从本地读一遍铺到界面上。
            // 注意这里读的还是**本地**，不是直接用服务器的返回值 ——
            // 这样"界面上显示的"和"数据库里存的"永远一致，不会出现对不上的情况。
            refreshFromLocal()
            AppLog.info(.data, "后台同步完成，耗时 \(Stopwatch.format(watch.milliseconds))")
        } catch SupabaseError.cancelled {
            // 任务被取消是正常情况（比如用户切换了登录状态），
            // 不该在日志里留一条"同步失败"吓人
            AppLog.info(.data, "后台同步已取消")
        } catch {
            AppLog.error(.data, "后台同步失败（界面不受影响）：\(String(describing: error))")
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

    /// 发一张图片。
    ///
    /// 【顺序：先落本地、立刻显示，再上传，最后把地址换成服务器上的】
    ///
    /// 不能"先上传再显示" —— 那样用户按下之后要盯着屏幕等几秒，
    /// 正是这个 App 最不该有的手感。
    ///
    /// 也不能"先发一条空消息、再补网址" —— 对方会先收到一条什么都没有的消息，
    /// 而且上传失败就留下一条永远补不上的空消息。
    ///
    /// 所以走的是**和文字消息同一条路**：本地先有一条（图片指向临时文件），
    /// 立刻可见、可重试；上传成功后把地址替换成服务器的。
    func sendImage(_ data: Data, to friendID: Friend.ID) async {
        // 落到临时文件，好让界面马上有东西可显示
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).jpg")
        guard (try? data.write(to: temp)) != nil else { return }

        let message = Message(
            friendID: friendID,
            text: "",
            imageURL: temp,
            sender: .me,
            status: .sending
        )
        persist(message)
        messagesByFriend[friendID, default: []].append(message)
        // 会话列表那一行的摘要显示「[图片]」而不是空白
        touch(friendID: friendID, last: "[图片]", at: message.sentAt)

        do {
            let remoteURL = try await AppServices.uploadChatImage(data)

            var ready = message
            ready.imageURL = remoteURL
            persist(ready)
            replace(message.id, in: friendID, with: ready)

            await deliver(ready)
        } catch {
            // 上传失败也要**如实说**，而且要能重试 ——
            // 悄悄失败的话，用户以为发出去了，对方根本没收到。
            var failed = message
            failed.status = .failed
            persist(failed)
            replace(message.id, in: friendID, with: failed)
            Haptics.warning()
        }
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

    // MARK: - 用户对自己数据的控制

    /// 删除一整个会话。界面会立刻变化，数据库那边也会真的删掉。
    func deleteConversation(_ friendID: Friend.ID) {
        local.deleteConversation(friendID: friendID)
        conversations.removeAll { $0.friend.id == friendID }
        messagesByFriend[friendID] = nil
    }

    /// 清空聊天记录，但保留这个好友
    func clearMessages(with friendID: Friend.ID) {
        local.clearMessages(with: friendID)
        messagesByFriend[friendID] = []
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }
        conversations[index].lastMessage = ""
        conversations[index].lastTime = .distantPast
        conversations[index].unreadCount = 0
    }

    /// 删除单条消息
    func deleteMessage(_ message: Message) {
        local.deleteMessage(id: message.id)
        messagesByFriend[message.friendID]?.removeAll { $0.id == message.id }
    }

    /// 拉黑 / 取消拉黑。
    ///
    /// 拉黑之后本地**立刻生效**两件事：
    ///   1. 对方再发消息不会进来（见下面的 receive）
    ///   2. 界面上有明确标记，用户知道自己拉黑了谁
    ///
    /// 说明：现在"拒收"是在本地做的。接上服务器后，服务器那边也会一起拦 ——
    /// 否则用户换台设备登录，拉黑就失效了。
    func setBlocked(_ blocked: Bool, for friendID: Friend.ID) {
        local.setBlocked(blocked, for: friendID)
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }
        conversations[index].isBlocked = blocked
    }

    func isBlocked(_ friendID: Friend.ID) -> Bool {
        conversations.first(where: { $0.friend.id == friendID })?.isBlocked ?? false
    }

    /// 举报一个好友。
    ///
    /// 现在只是**记在本地**。接上 Supabase 之后，这里会多一步上报到服务器。
    /// 但界面完全不用改 —— 因为调用它的地方只认这个方法名。
    func report(_ friendID: Friend.ID, reason: ReportReason, note: String = "") {
        local.saveReport(Report(friendID: friendID, reason: reason, note: note))
    }

    /// 用邀请码加好友。
    ///
    /// 出错时**抛出去**而不是自己吞掉 —— 界面要告诉用户
    /// "码不对"还是"已经是好友了"，这两种情况该说的话完全不一样。
    func addFriend(inviteCode: String) async throws {
        let friend = try await remote.addFriend(inviteCode: inviteCode)
        local.save(friend: friend)
        refreshFromLocal()
    }

    /// 本地搜索：在**好友名字**和**消息内容**里找。
    ///
    /// 全程在内存里做，不碰网络 —— 所以是"边打字边出结果"。
    /// 代价是数据量大到几万条时会慢，那时候要改成数据库查询
    ///（`LocalStore` 里加一个带 `#Predicate` 的 search）。
    /// 现在的量级（几百条）完全够用。
    func search(_ keyword: String) -> [SearchHit] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= 1 else { return [] }

        var hits: [SearchHit] = []

        for conversation in conversations {
            let friend = conversation.friend

            if friend.name.lowercased().contains(needle) {
                hits.append(SearchHit(id: "f-\(friend.id)", kind: .friend,
                                      friend: friend, text: friend.name, date: nil))
            }

            for message in messagesByFriend[friend.id] ?? []
            where message.text.lowercased().contains(needle) {
                hits.append(SearchHit(id: "m-\(message.id)", kind: .message,
                                      friend: friend, text: message.text,
                                      date: message.sentAt))
            }
        }

        // 好友命中排前面（找人通常比找一句话更常见），
        // 同一类里按时间从新到旧
        return hits.sorted { a, b in
            if a.kind != b.kind { return a.kind == .friend }
            return a.sortKey > b.sortKey
        }
    }

    /// 找某个好友对应的会话（从搜索结果跳进聊天页要用）
    func conversation(for friendID: Friend.ID) -> Conversation? {
        conversations.first { $0.friend.id == friendID }
    }

    /// 注销账号 / 清空全部数据。
    ///
    /// 现在只清本地（因为我们还没接服务器）。
    /// **接上 Supabase 之后，这里会多一步调服务器删除**，界面完全不用改。
    func deleteEverything() {
        local.deleteEverything()
        conversations = []
        messagesByFriend = [:]
    }

    /// 这个好友被举报过几次
    func reportCount(for friendID: Friend.ID) -> Int {
        local.reports(for: friendID).count
    }

    // MARK: - 小助手

    /// 构造交给小助手的上下文。
    ///
    /// 两件事刻意收在这里，而不是让界面自己拼：
    ///   1. **只取最近若干条**（见 AssistantContext.recentLimit）——
    ///      判断"对方这句话什么意思"根本用不着三个月的聊天记录。
    ///      能少发就少发，这是处理别人聊天内容时该有的自觉。
    ///   2. 上下文由数据层统一提供，以后要加"排除已删除消息"之类的规则，
    ///      只改这一处。
    func assistantContext(for friendID: Friend.ID, friendName: String) -> AssistantContext {
        let recent = messages(with: friendID).suffix(AssistantContext.recentLimit)
        return AssistantContext(friendName: friendName, messages: Array(recent))
    }

    // MARK: - 未读

    /// 进入某个会话时清掉未读小红点
    func markRead(_ friendID: Friend.ID) {
        setUnread(0, for: friendID)
    }

    /// 设置未读数（0 = 已读，1 = 手动标记成未读）
    func setUnread(_ count: Int, for friendID: Friend.ID) {
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }
        conversations[index].unreadCount = count
        local.setUnread(count, for: friendID)   // 一起写进数据库，重启后不会又冒出来
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

    /// 收到一条好友消息。
    ///
    /// 不是 private 是因为开发自检要用它假造一条进来的消息
    ///（假服务器没有实时推送，没法真的收）。
    func receive(_ message: Message) {
        // ① 已经被拉黑的人，消息直接丢掉 —— 不进数据库，也不进界面。
        //    这才是"拉黑"真正起作用的地方：只把列表里的会话藏起来是不够的。
        if isBlocked(message.friendID) { return }

        // ② 去重：同一条消息只存一次（网络偶尔会重复推送，这是必须防的）
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
