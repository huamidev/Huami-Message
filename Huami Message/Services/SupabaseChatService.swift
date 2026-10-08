import Foundation

// ============================================================================
// 真·聊天服务（Supabase）
// ============================================================================
//
// 和 `MockChatService` 实现同一个协议，所以界面一行都不用改。
//
// 用到的接口（都是 Supabase 标准接口，没有自定义后端）：
//
//   GET  /rest/v1/friendships            我的好友列表
//   GET  /rest/v1/profiles               好友的昵称和头像色
//   GET  /rest/v1/messages               消息（按"我和某人之间"过滤）
//   POST /rest/v1/messages               发消息
//   POST /rest/v1/rpc/add_friend_by_username  用用户名加好友
//   WS   /realtime/v1/websocket          实时收新消息
//
// ============================================================================

final class SupabaseChatService: ChatService {

    private let client: SupabaseClient

    /// 不是演示数据 —— 界面顶部那条「演示数据」提示会自动消失
    let isDemoData = false

    init(client: SupabaseClient) {
        self.client = client
    }

    /// 当前登录用户的 id。登录之后由 `SupabaseAuthService` 写进客户端。
    private var myID: UUID? { client.currentUserID }

    // ========================================================================
    // 会话列表
    // ========================================================================

    func loadConversations() async throws -> [Conversation] {
        // 没登录就返回空的 —— 不该崩，也不该发没意义的请求
        guard let myID else { return [] }
        let me = myID.uuidString.lowercased()

        // ① 我加的好友。
        //    好友关系在数据库里存**两行**（我→他、他→我），
        //    这里只查 user_id = 我 的那些，也就是"我认可的"。
        let links: [FriendshipRow] = try await client.get(
            "/rest/v1/friendships",
            query: [
                URLQueryItem(name: "select", value: "friend_id,blocked"),
                URLQueryItem(name: "user_id", value: "eq.\(me)"),
            ],
            as: [FriendshipRow].self
        )
        guard !links.isEmpty else { return [] }

        // ② 他们的档案。
        //    ⚠️ 用 `in.(...)` **一次查完**，而不是一个好友查一次 ——
        //    后者就是"N 个好友 N 次请求"，好友一多列表就会转圈。
        let ids = links.map { $0.friendId.uuidString.lowercased() }.joined(separator: ",")
        let profiles: [ProfileRow] = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(ids))"),
            ],
            as: [ProfileRow].self
        )
        let profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        // ③ 最近的消息，用来填"最后一条说了什么"。
        //    只取最近 200 条：会话列表每个会话只要最后一条，
        //    没必要把几年的历史全拉下来（那会很慢，也很费流量）。
        let recent: [MessageRow] = try await client.get(
            "/rest/v1/messages",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "or", value: "(sender_id.eq.\(me),recipient_id.eq.\(me))"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "200"),
            ],
            as: [MessageRow].self
        )

        // 按时间倒序拿到的，所以**第一次遇到某个人时那条就是最新的**
        var lastByFriend: [UUID: MessageRow] = [:]
        for row in recent {
            let other = row.otherParty(myID: myID)
            if lastByFriend[other] == nil { lastByFriend[other] = row }
        }

        return links
            .compactMap { link -> Conversation? in
                // 档案读不到就跳过这个人（比如对方注销了账号）
                guard let profile = profileByID[link.friendId] else { return nil }
                let last = lastByFriend[link.friendId]
                return Conversation(
                    friend: Friend(id: profile.id,
                                   name: profile.displayName,
                                   avatarSeed: profile.avatarSeed),
                    lastMessage: last?.body ?? "",
                    lastTime: last?.createdAt ?? .distantPast,
                    // 未读数是**本地**记的：服务器没有已读回执，
                    // 也不该知道你在哪台设备上读到哪儿了
                    unreadCount: 0,
                    isBlocked: link.blocked
                )
            }
            .sorted { $0.lastTime > $1.lastTime }
    }

    func removeFriend(_ id: Friend.ID) async throws {
        // 走数据库函数，因为它要在服务端**一次删两行**（我→他、他→我）。
        // 客户端直连 DELETE 只能删到自己那行，见 supabase/remove-friend.sql。
        let ok: Bool = try await client.post(
            "/rest/v1/rpc/remove_friend",
            body: TargetBody(target: id.uuidString.lowercased()),
            as: Bool.self
        )
        guard ok else { throw ChatError.network }
    }

    // ========================================================================
    // 某个会话的消息
    // ========================================================================

    func loadMessages(with friendID: Friend.ID) async throws -> [Message] {
        guard let myID else { return [] }
        let me = myID.uuidString.lowercased()
        let other = friendID.uuidString.lowercased()

        let rows: [MessageRow] = try await client.get(
            "/rest/v1/messages",
            query: [
                URLQueryItem(name: "select", value: "*"),
                // 「我发给他的」或者「他发给我的」。
                // PostgREST 的 or/and 可以嵌套，这一句就是标准的"两人之间的消息"。
                URLQueryItem(name: "or",
                             value: "(and(sender_id.eq.\(me),recipient_id.eq.\(other)),"
                                  + "and(sender_id.eq.\(other),recipient_id.eq.\(me)))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                // 第一版先限 500 条。翻更早的历史要分页，以后再说 ——
                // 现在聊天框里有个"往上翻到底"的边界，但不会把 App 卡死。
                URLQueryItem(name: "limit", value: "500"),
            ],
            as: [MessageRow].self
        )

        return rows.map { $0.asMessage(myID: myID) }
    }

    // ========================================================================
    // 发消息
    // ========================================================================

    func send(_ message: Message) async throws -> Message {
        guard let myID else { throw ChatError.network }

        let payload = NewMessageRow(
            id: message.id,
            senderId: myID,
            recipientId: message.friendID,
            body: message.text,
            imageUrl: message.imageURL?.absoluteString,
            polishedWith: message.polishedWith?.rawValue
        )

        let rows: [MessageRow] = try await client.post(
            "/rest/v1/messages",
            body: payload,
            // 让服务器把插入后的那一行**回传给我们**。
            // 不回传的话就拿不到服务器写的时间戳，两台设备上的顺序会对不上。
            prefer: "return=representation",
            as: [MessageRow].self
        )

        // 用服务器返回的那一行覆盖本地版本（主要是拿它写的时间）
        return rows.first?.asMessage(myID: myID) ?? message
    }

    // ========================================================================
    // 加好友
    // ========================================================================

    func addFriend(username: String) async throws -> Friend {
        let name = Username.normalize(username)
        guard Username.isValid(name) else { throw ChatError.usernameNotFound }

        // 加好友要往数据库写**两行**（我→他、他→我）。
        // 让客户端分两次写是不安全的（可能只成功一半），
        // 所以做成了一个数据库函数，那边一次搞定。见 supabase/schema.sql。
        let friendID: UUID
        do {
            friendID = try await client.post(
                "/rest/v1/rpc/add_friend_by_username",
                body: UsernameBody(username: name),
                as: UUID.self
            )
        } catch {
            throw Self.translateAddFriend(error)
        }

        // 拿到 id 之后把档案读出来（昵称、头像色）—— 界面要立刻能显示这个人
        let profiles: [ProfileRow] = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(friendID.uuidString.lowercased())"),
                URLQueryItem(name: "limit", value: "1"),
            ],
            as: [ProfileRow].self
        )
        guard let profile = profiles.first else { throw ChatError.usernameNotFound }

        return Friend(id: profile.id, name: profile.displayName, avatarSeed: profile.avatarSeed)
    }

    /// 把数据库函数抛出的错误翻成人话。
    /// 数据库函数里用的是 `raise exception '没有这个人'`，所以文案本来就是中文。
    private static func translateAddFriend(_ error: Error) -> Error {
        guard case SupabaseError.http(_, let message) = error else { return error }
        if message.contains("没有这个人") { return ChatError.usernameNotFound }
        if message.contains("不能加自己") { return ChatError.cannotAddSelf }
        return error
    }

    // ========================================================================
    // 实时收消息
    // ========================================================================

    func incomingMessages() -> AsyncStream<Message> {
        AsyncStream { continuation in
            guard let myID else {
                continuation.finish()
                return
            }

            let realtime = SupabaseRealtime(
                config: client.config,
                accessToken: client.accessToken,
                userID: myID
            )

            let task = Task {
                for await row in realtime.records() {
                    if Task.isCancelled { break }
                    continuation.yield(row.asMessage(myID: myID))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                realtime.disconnect()
            }
        }
    }
}

// ============================================================================
// 服务器上的数据形状
// ============================================================================
//
// 【为什么这些结构体和数据库字段一一对应，而不是直接用 Message】
//
// 因为"服务器上的样子"和"界面要用的样子"是两回事：
//   · 服务器存 sender_id / recipient_id，界面要的是"我发的还是他发的"
//   · 服务器的时间戳是权威的，界面的时间是本地乐观填的
//
// 中间隔一层，以后改数据库结构时只要改这一层，界面不受影响。
// ============================================================================

struct FriendshipRow: Decodable {
    let friendId: UUID
    let blocked: Bool
}

/// `profiles` 表的一行。
/// 登录和聊天两处共用 —— 分开定义会两边慢慢长歪。
struct ProfileRow: Decodable {
    let id: UUID
    let displayName: String
    let avatarSeed: Int
    let username: String?

    /// 头像照片网址。同样可选 —— 没上传过的人这一项是空的。
    let avatarUrl: String?

    /// 简介。
    ///
    /// ⚠️ **必须是可选的，而且查询要用 `select=*`。**
    ///
    /// 因为 `bio` 这一列是后来才加的（要用户在 SQL Editor 里跑一句
    /// `alter table ... add column bio`）。在他跑之前：
    ///   · 用 `select=*` → 返回里没有 bio 这个键 → 可选值解码成 nil ✓
    ///   · 用 `select=...,bio` → PostgREST 直接报"列不存在" ✗ 整个功能挂掉
    ///
    /// 这样写，**加字段前后都能正常工作** —— 用户什么时候跑那句 SQL 都行。
    let bio: String?
}

struct MessageRow: Decodable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let body: String
    let imageUrl: String?
    let polishedWith: String?
    let createdAt: Date

    /// 这条消息的另一方是谁（对我而言）
    func otherParty(myID: UUID) -> UUID {
        senderId == myID ? recipientId : senderId
    }

    func asMessage(myID: UUID) -> Message {
        let mine = senderId == myID
        return Message(
            id: id,
            friendID: otherParty(myID: myID),
            text: body,
            imageURL: imageUrl.flatMap(URL.init(string:)),
            sender: mine ? .me : .friend,
            sentAt: createdAt,
            polishedWith: polishedWith.flatMap(PolishStyle.init(rawValue:)),
            // 从服务器来的消息一律是"已发送" —— 服务器说有就是有
            status: .sent
        )
    }
}

struct NewMessageRow: Encodable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let body: String
    let imageUrl: String?
    let polishedWith: String?
}

/// 加好友时发给数据库函数的参数。
/// 键名必须和函数签名里的参数名一致（`username`）。
/// 只传一个目标 id 的请求体（删好友用）。
private struct TargetBody: Encodable {
    let target: String
}

private struct UsernameBody: Encodable {
    let username: String
}
