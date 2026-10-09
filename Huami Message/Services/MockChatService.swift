import Foundation

/// 假数据版的聊天服务 —— 接真服务器之前都用它。
///
/// 它的作用：让你在**完全不用注册账号、不用连网**的情况下，
/// 先把界面和手感做到位。等界面满意了，我们再写 SupabaseChatService 把它换掉。
///
/// 这里故意加了 160 毫秒的延迟，是为了模拟真实网络，
/// 让我们提前看到「等服务器」时的界面表现 —— 真机上这一步是必然会有的。
/// 如果现在不把「等待」和「失败」这两件事设计好，接了真后端就会到处卡顿、到处丢消息。
final class MockChatService: ChatService {

    // MARK: - 内部状态（全部在内存里）

    private var friends: [Friend] = []
    private var messages: [Friend.ID: [Message]] = [:]

    /// 用来把新消息「推」给界面
    private var continuation: AsyncStream<Message>.Continuation?

    /// 每个好友的自动回复轮到第几句了
    private var replyCursor: [Friend.ID: Int] = [:]

    /// 模拟网络往返的耗时
    private let latency: Duration = .milliseconds(160)

    init() {
        seed()
    }

    // MARK: - ChatService

    /// 假数据 —— 界面上会显示一个「演示数据」的标识
    let isDemoData = true

    func loadConversations() async throws -> [Conversation] {
        try await Task.sleep(for: latency)

        // 会话列表不是单独存一份，而是从消息里「推导」出来的。
        // 好处：永远不会有「会话列表说 A，消息记录说 B」这种不同步的 bug。
        let list = friends.map { friend -> Conversation in
            let last = messages[friend.id]?.last
            return Conversation(
                friend: friend,
                lastMessage: last?.text ?? "",
                lastTime: last?.sentAt ?? .distantPast,
                unreadCount: 0
            )
        }
        return list.sorted { $0.lastTime > $1.lastTime }
    }

    func loadMessages(with friendID: Friend.ID) async throws -> [Message] {
        try await Task.sleep(for: latency)
        return messages[friendID] ?? []
    }

    func send(_ message: Message, isGroup: Bool) async throws -> Message {
        try await Task.sleep(for: latency)

        // 调试开关：强制失败，用来验证「发送失败 + 重试」的界面。
        if DevFlags.failSend {
            throw MockChatError.sendFailed
        }

        // 真后端在这里会返回"服务器确认后的那条消息"，并且在服务器上把它记为已送达。
        // 所以假服务也把**确认后的版本**存进自己的列表 ——
        // 存的如果还是"发送中"的版本，下次后台同步就会拿它去覆盖本地，把状态冲掉。
        var confirmed = message
        confirmed.status = .sent
        messages[message.friendID, default: []].append(confirmed)
        scheduleAutoReply(to: message.friendID)
        return confirmed
    }

    func incomingMessages() -> AsyncStream<Message> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// 用用户名加好友（假实现）。
    ///
    /// 真的实现是把这个码发给服务器、服务器去查这个人是谁。
    /// 假实现没法查，所以**从用户名本身派生出一个稳定的假好友** ——
    /// 同一个码永远得到同一个人。
    ///
    /// 这一点很重要：如果每次加都随机生成一个人，
    /// 那"加两次会不会变成两个好友"这类问题就永远测不出来。
    func findProfile(username: String) async throws -> ProfileSummary {
        let name = Username.normalize(username)
        guard Username.isValid(name) else { throw ChatError.usernameNotFound }
        // 示例模式下没有别人，永远找不到
        throw ChatError.usernameNotFound
    }

    func sendFriendRequest(username: String, note: String?) async throws {
        throw ChatError.usernameNotFound
    }

    func loadIncomingRequests() async throws -> [FriendRequest] { [] }

    func respondToRequest(_ id: FriendRequest.ID, accept: Bool) async throws {}

    func removeFriend(_ id: Friend.ID) async throws {
        // 示例模式下没有"服务器上的关系"要解除，本地清掉就够了
    }

    func addFriend(username: String) async throws -> Friend {
        try await Task.sleep(for: latency)

        let code = Username.normalize(username)
        guard Username.isValid(code) else { throw ChatError.usernameNotFound }

        let id = Self.friendID(fromCode: code)
        if let existing = friends.first(where: { $0.id == id }) {
            throw ChatError.alreadyFriends(existing.name)
        }

        let friend = Friend(
            id: id,
            name: Self.strangerName(for: code),
            avatarSeed: Int(code.utf8.first ?? 0) % 6
        )
        friends.append(friend)
        messages[friend.id] = []
        return friend
    }

    // MARK: - 模拟「好友回你一句」

    /// 隔 2.5 秒让好友回一句 —— 用来演示「实时收消息，界面自动更新」。
    /// 真接入 Supabase 后，这段会被服务器的推送取代，界面完全不用改。
    private func scheduleAutoReply(to friendID: Friend.ID) {
        let pool = Self.replyPool[friendID] ?? ["嗯嗯"]
        let cursor = replyCursor[friendID, default: 0]
        replyCursor[friendID] = cursor + 1
        let text = pool[cursor % pool.count]

        Task {
            try? await Task.sleep(for: .seconds(2.5))
            // 自动回复也要用固定的 id，否则每次重启都会在数据库里多出一条重复的
            let reply = Message(
                id: Self.replyID(friendID: friendID, index: cursor),
                friendID: friendID,
                text: text,
                sender: .friend
            )
            messages[friendID, default: []].append(reply)
            continuation?.yield(reply)
        }
    }

    // MARK: - 假数据

    /// 好友的自动回复台词库，每个好友性格不同
    private static var replyPool: [Friend.ID: [String]] = [:]

    // MARK: 稳定的 id（很重要，别改回随机 UUID）

    /// ⚠️ 这里必须是**固定不变**的 id，不能用 UUID() 每次随机生成。
    ///
    /// 原因：现在消息会真的存进本地数据库。
    /// 如果每次启动假数据的 id 都变，数据库里就会不停地**新增重复的消息** ——
    /// 开三次 App 就有三份「在吗」。
    ///
    /// 这个坑很隐蔽：单次运行完全正常，只有反复重启才会暴露出来。
    /// 真服务器上每条消息的 id 也是由服务器生成的、永远不变，所以这样做反而更真实。
    /// ⚠️ 格式核对：UUID 必须是 8-4-4-4-12 共 36 个字符。
    ///    下面 format 里已经带了 "-0000-0000-0000-"，所以 prefix 只能给第一组 8 位。
    ///    （我第一版把 prefix 写成 "11111111-1111"，多了一组，凑成 41 个字符，
    ///      UUID(uuidString:) 返回 nil，强制解包直接崩溃。
    ///      崩溃栈非常明确 —— 这就是"宁可崩得清清楚楚，也不要错得莫名其妙"。）
    private static func id(_ prefix: String, _ n: Int) -> UUID {
        UUID(uuidString: String(format: "\(prefix)-0000-0000-0000-%012d", n))!
    }

    private static func friendID(_ n: Int) -> UUID { id("11111111", n) }

    /// 用户名 → 稳定的 UUID。
    ///
    /// ⚠️ 这里**故意不用 `UUID(uuidString:)!`**。
    /// 我在这个文件里已经被强制解包坑过一次了（见上面 id() 的注释）。
    /// 直接用 16 个字节构造，没有"字符串格式对不对"这一层，也就没有崩的可能。
    private static func friendID(fromCode code: String) -> UUID {
        var bytes = Array(code.utf8)
        // 不足 16 字节用 '0' 补齐 —— 必须是确定性的，不能随机
        while bytes.count < 16 { bytes.append(0x30) }
        let b = Array(bytes.prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// 陌生的"新好友"名字。同一用户名永远得到同一个人。
    private static let strangerNames = [
        "周叙", "许一诺", "陆沉", "沈知遥", "顾南", "程也", "白露", "闻笛",
    ]

    private static func strangerName(for code: String) -> String {
        // 用字节和算一个稳定的下标（不用 hashValue —— 它每个进程都不一样）
        let sum = code.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFF }
        return strangerNames[sum % strangerNames.count]
    }
    private static func seedMessageID(_ n: Int) -> UUID { id("22222222", n) }

    /// 自动回复的 id：同一个好友的第 n 句回复，永远是同一个 id
    private static func replyID(friendID: UUID, index: Int) -> UUID {
        // ⚠️ 绝对不能用 friendID.hashValue —— Swift 的哈希值每个进程都会重新随机，
        //    那样每次启动算出来的 id 都不一样，"稳定"就无从谈起。
        //    必须从 UUID 的字节里直接算，才是真正固定的。
        let bytes = withUnsafeBytes(of: friendID.uuid) { Array($0) }
        let stable = (Int(bytes[0]) << 8) | Int(bytes[1])
        return UUID(uuidString: String(format: "33333333-3333-3333-%04d-%012d", stable % 10000, index))!
    }

    /// 造一份像样的假数据。
    /// 数据故意做得「有故事」：林一那句是留给「小助手」演示用的。
    private func seed() {
        let linYi   = Friend(id: Self.friendID(1), name: "林一", avatarSeed: 0)
        let chenXu  = Friend(id: Self.friendID(2), name: "陈叙", avatarSeed: 1)
        let mom     = Friend(id: Self.friendID(3), name: "妈妈", avatarSeed: 2)
        let laoZhou = Friend(id: Self.friendID(4), name: "老周", avatarSeed: 3)

        friends = [linYi, chenXu, mom, laoZhou]

        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        // 林一：主要演示对象。
        // 故意让前几句落在**昨天**、最后一句落在**今天**，
        // 这样聊天页会出现两条日期分隔条（昨天 / 今天），效果一眼可见。
        messages[linYi.id] = [
            Message(id: Self.seedMessageID(1), friendID: linYi.id, text: "在吗", sender: .friend, sentAt: ago(1500)),
            Message(id: Self.seedMessageID(2), friendID: linYi.id, text: "在，怎么了", sender: .me, sentAt: ago(1496)),
            Message(id: Self.seedMessageID(3), friendID: linYi.id, text: "周五晚上的事，你来吗", sender: .friend, sentAt: ago(1495)),
            Message(id: Self.seedMessageID(4), friendID: linYi.id, text: "应该可以", sender: .me, sentAt: ago(1490)),
            Message(id: Self.seedMessageID(5), friendID: linYi.id, text: "你昨天怎么没来？大家都等你很久了", sender: .friend, sentAt: ago(12)),
        ]

        // 开发用：灌一批填充消息，用来测长列表
        let extra = DevFlags.seedMany
        if extra > 0 {
            var filler: [Message] = []
            for i in 0..<extra {
                filler.append(Message(
                    id: Self.seedMessageID(1000 + i),
                    friendID: linYi.id,
                    text: "填充消息 #\(i + 1) —— 用来测长列表的滚动和性能",
                    sender: i % 2 == 0 ? .friend : .me,
                    // 时间排在最老的那一批之前，别打乱原有演示数据
                    sentAt: ago(2000 + Double(extra - i) * 400)
                ))
            }
            messages[linYi.id] = filler + (messages[linYi.id] ?? [])
        }

        // 陈叙：同事，说话比较公事
        messages[chenXu.id] = [
            Message(id: Self.seedMessageID(11), friendID: chenXu.id, text: "在忙吗", sender: .friend, sentAt: ago(150)),
            Message(id: Self.seedMessageID(12), friendID: chenXu.id, text: "还好，怎么了", sender: .me, sentAt: ago(148)),
            Message(id: Self.seedMessageID(13), friendID: chenXu.id, text: "方案我改好了，第二页那个数据麻烦你核一下", sender: .friend, sentAt: ago(90)),
        ]

        // 妈妈
        messages[mom.id] = [
            Message(id: Self.seedMessageID(21), friendID: mom.id, text: "吃饭了吗", sender: .friend, sentAt: ago(1500)),
            Message(id: Self.seedMessageID(22), friendID: mom.id, text: "吃了", sender: .me, sentAt: ago(1495)),
            Message(id: Self.seedMessageID(23), friendID: mom.id, text: "降温了，记得加衣服", sender: .friend, sentAt: ago(1440)),
        ]

        // 老周
        messages[laoZhou.id] = [
            Message(id: Self.seedMessageID(31), friendID: laoZhou.id, text: "球局周日老地方，来不来", sender: .friend, sentAt: ago(2900)),
        ]

        Self.replyPool = [
            linYi.id:   ["嗯嗯", "哈哈哈行", "那说好了啊", "我先忙，晚点聊"],
            chenXu.id:  ["收到，谢谢", "好，我看看", "行，那就这么定"],
            mom.id:     ["好，你忙吧", "记得早点睡", "知道了，别熬夜"],
            laoZhou.id: ["行，那我占位子了", "来吧，就差你了", "好嘞"],
        ]
    }
}

/// 假服务会抛出的错误。
/// 真接上 Supabase 之后，这里会换成网络层的错误（超时、没网、服务器 500……）。
enum MockChatError: Error {
    case sendFailed
}
