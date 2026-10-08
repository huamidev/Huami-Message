import Foundation

/// 假数据版的聊天服务 —— 第 0 步专用。
///
/// 它的作用：让你在**完全不用注册账号、不用连网**的情况下，
/// 先把界面和手感做到位。等界面满意了，我们再写 SupabaseChatService 把它换掉。
///
/// 这里故意加了 160 毫秒的延迟，是为了模拟真实网络，
/// 让我们提前看到「等服务器」时的界面表现 —— 真机上这一步是必然会有的。
/// 如果现在不把「等待」这件事设计好，接了真后端就会到处卡顿。
final class MockChatService: ChatService {

    // MARK: - 内部状态（全部在内存里，App 杀掉重开就回到初始样子）

    private var friends: [Friend] = []
    private var messages: [Friend.ID: [Message]] = [:]
    private var unread: [Friend.ID: Int] = [:]

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
                unreadCount: unread[friend.id] ?? 0
            )
        }
        // 最近说话的排最前面
        return list.sorted { $0.lastTime > $1.lastTime }
    }

    func loadMessages(with friendID: Friend.ID) async throws -> [Message] {
        try await Task.sleep(for: latency)
        return messages[friendID] ?? []
    }

    func send(_ message: Message) async throws -> Message {
        try await Task.sleep(for: latency)
        messages[message.friendID, default: []].append(message)
        scheduleAutoReply(to: message.friendID)
        // 假服务：原样返回（id 和时间都不变，这样界面上不会闪一下）。
        // 真后端会返回服务器生成的时间和编号，处理方式一样。
        return message
    }

    func incomingMessages() -> AsyncStream<Message> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
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
            let reply = Message(friendID: friendID, text: text, sender: .friend)
            messages[friendID, default: []].append(reply)
            continuation?.yield(reply)
        }
    }

    // MARK: - 假数据

    /// 好友的自动回复台词库，每个好友性格不同
    private static var replyPool: [Friend.ID: [String]] = [:]

    /// 造一份像样的假数据。
    /// 数据故意做得「有故事」：林一那句是留给「军师」演示用的。
    private func seed() {
        let linYi   = Friend(name: "林一", avatarSeed: 0)
        let chenXu  = Friend(name: "陈叙", avatarSeed: 1)
        let mom     = Friend(name: "妈妈", avatarSeed: 2)
        let laoZhou = Friend(name: "老周", avatarSeed: 3)

        friends = [linYi, chenXu, mom, laoZhou]

        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        // 林一：主要演示对象
        messages[linYi.id] = [
            Message(friendID: linYi.id, text: "在吗", sender: .friend, sentAt: ago(600)),
            Message(friendID: linYi.id, text: "在，怎么了", sender: .me, sentAt: ago(596)),
            Message(friendID: linYi.id, text: "周五晚上的事，你来吗", sender: .friend, sentAt: ago(595)),
            Message(friendID: linYi.id, text: "应该可以", sender: .me, sentAt: ago(590)),
            Message(friendID: linYi.id, text: "你昨天怎么没来？大家都等你很久了", sender: .friend, sentAt: ago(12)),
        ]
        unread[linYi.id] = 2

        // 陈叙：同事，说话比较公事
        messages[chenXu.id] = [
            Message(friendID: chenXu.id, text: "在忙吗", sender: .friend, sentAt: ago(150)),
            Message(friendID: chenXu.id, text: "还好，怎么了", sender: .me, sentAt: ago(148)),
            Message(friendID: chenXu.id, text: "方案我改好了，第二页那个数据麻烦你核一下", sender: .friend, sentAt: ago(90)),
        ]

        // 妈妈
        messages[mom.id] = [
            Message(friendID: mom.id, text: "吃饭了吗", sender: .friend, sentAt: ago(1500)),
            Message(friendID: mom.id, text: "吃了", sender: .me, sentAt: ago(1495)),
            Message(friendID: mom.id, text: "降温了，记得加衣服", sender: .friend, sentAt: ago(1440)),
        ]

        // 老周
        messages[laoZhou.id] = [
            Message(friendID: laoZhou.id, text: "球局周日老地方，来不来", sender: .friend, sentAt: ago(2900)),
        ]

        Self.replyPool = [
            linYi.id:   ["嗯嗯", "哈哈哈行", "那说好了啊", "我先忙，晚点聊"],
            chenXu.id:  ["收到，谢谢", "好，我看看", "行，那就这么定"],
            mom.id:     ["好，你忙吧", "记得早点睡", "知道了，别熬夜"],
            laoZhou.id: ["行，那我占位子了", "来吧，就差你了", "好嘞"],
        ]
    }
}
