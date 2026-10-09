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
        // ⚠️ 这里**不能**在 links 为空时直接返回 ——
        //    一个只有群、没加好友的用户，会话列表会整个空掉。
        //    （我第一版就是 `guard !links.isEmpty else { return [] }`。）

        // ② 他们的档案。
        //    ⚠️ 用 `in.(...)` **一次查完**，而不是一个好友查一次 ——
        //    后者就是"N 个好友 N 次请求"，好友一多列表就会转圈。
        //
        //    好友为空时**跳过这次请求**：`in.()` 里没内容会拼出一个
        //    语法不合法的查询，服务器直接报错。
        var profiles: [ProfileRow] = []
        if !links.isEmpty {
        let ids = links.map { $0.friendId.uuidString.lowercased() }.joined(separator: ",")
        profiles = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(ids))"),
            ],
            as: [ProfileRow].self
        )
        }
        // ⚠️ 不用 Dictionary(uniqueKeysWithValues:) ——
        //    它遇到重复 key 会**直接崩**。服务端数据万一有重复，
        //    这里就是用户一打开 App 就闪退。循环写安全得多。
        var profileByID: [UUID: ProfileRow] = [:]
        for profile in profiles { profileByID[profile.id] = profile }

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
            // otherParty 现在是可选的（群消息没有"对方"，只有"哪段对话"）。
            // 解不出来的行直接跳过 —— 一条脏数据不该让整个会话列表崩掉。
            guard let other = row.otherParty(myID: myID) else { continue }
            if lastByFriend[other] == nil { lastByFriend[other] = row }
        }

        let direct = links
            .compactMap { link -> Conversation? in
                // 档案读不到就跳过这个人（比如对方注销了账号）
                guard let profile = profileByID[link.friendId] else { return nil }
                let last = lastByFriend[link.friendId]
                return Conversation(
                    friend: Friend(id: profile.id,
                                   name: profile.displayName,
                                   avatarSeed: profile.avatarSeed,
                                   avatarURL: profile.avatarUrl.flatMap(URL.init(string:))),
                    lastMessage: last?.asMessage(myID: myID).preview ?? "",
                    lastTime: last?.createdAt ?? .distantPast,
                    // 未读数是**本地**记的：服务器没有已读回执，
                    // 也不该知道你在哪台设备上读到哪儿了
                    unreadCount: 0,
                    isBlocked: link.blocked
                )
            }
        // ③ 我参与的群
        //
        // ⚠️ **这里绝对不能写 `try await`。**
        //
        // 我第一版就是那么写的，结果群那边一出问题，
        // **好友列表跟着整个空掉**、添加好友报"已是好友"、
        // 消息也收不到 —— 因为 loadConversations 整个抛出去了。
        //
        // 群是新功能，好友是老的、每天都用的。
        // **新功能出错不该让老功能也挂掉。** 拉不到群就当成没有群，
        // 但一定要把原因打出来，不能静默。
        var groups: [Conversation] = []
        do {
            groups = try await loadGroups(myID: myID)
            AppLog.info(.data, "群聊：\(groups.count) 个")
        } catch {
            AppLog.error(.network, "拉群失败（好友列表不受影响）：\(describeLoadError(error))")
        }

        return (direct + groups).sorted { $0.lastTime > $1.lastTime }
    }

    /// 我参与的群聊。
    ///
    /// 两步查询：先问"我参与了哪些对话"，再按 id 一次把群信息查回来。
    /// 和好友那边一样，**不能一个群查一次**。
    private func loadGroups(myID: UUID) async throws -> [Conversation] {
        let me = myID.uuidString.lowercased()

        struct MemberRow: Decodable { let conversationId: UUID }
        let memberships: [MemberRow] = try await client.get(
            "/rest/v1/conversation_members",
            query: [
                URLQueryItem(name: "select", value: "conversation_id"),
                URLQueryItem(name: "user_id", value: "eq.\(me)"),
            ],
            as: [MemberRow].self
        )
        guard !memberships.isEmpty else { return [] }

        struct GroupRow: Decodable {
            let id: UUID
            let title: String?
            let avatarSeed: Int
        }
        let ids = Set(memberships.map { $0.conversationId.uuidString.lowercased() })
            .joined(separator: ",")
        let rows: [GroupRow] = try await client.get(
            "/rest/v1/conversations",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(ids))"),
                // 只取群。一对一将来也会进这张表（第二步的迁移做完之后），
                // 现在先挡一道，免得两种数据混进来。
                URLQueryItem(name: "kind", value: "eq.group"),
            ],
            as: [GroupRow].self
        )

        return rows.map { row in
            Conversation(
                friend: Friend(id: row.id,
                               name: row.title ?? "群聊",
                               avatarSeed: row.avatarSeed,
                               kind: .group,
                               title: row.title),
                lastMessage: "",
                lastTime: .distantPast,
                unreadCount: 0,
                isBlocked: false
            )
        }
    }

    // ========================================================================
    // 好友申请
    // ========================================================================

    func findProfile(username: String) async throws -> ProfileSummary {
        let name = Username.normalize(username)
        guard Username.isValid(name) else { throw ChatError.usernameNotFound }

        let rows: [ProfileRow] = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "username", value: "eq.\(name)"),
                URLQueryItem(name: "limit", value: "1"),
            ],
            as: [ProfileRow].self
        )
        guard let row = rows.first else { throw ChatError.usernameNotFound }

        return ProfileSummary(id: row.id,
                              displayName: row.displayName,
                              username: row.username ?? "",
                              avatarSeed: row.avatarSeed,
                              avatarURL: row.avatarUrl.flatMap(URL.init(string:)))
    }

    func sendFriendRequest(username: String, note: String?) async throws {
        let name = Username.normalize(username)
        guard Username.isValid(name) else { throw ChatError.usernameNotFound }

        do {
            let _: UUID = try await client.post(
                "/rest/v1/rpc/send_friend_request",
                body: SendRequestBody(targetUsername: name, note: note),
                as: UUID.self
            )
        } catch {
            throw Self.translateRequestError(error)
        }
    }

    func loadIncomingRequests() async throws -> [FriendRequest] {
        guard let myID else { return [] }

        let rows: [FriendRequestRow] = try await client.get(
            "/rest/v1/friend_requests",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "to_id", value: "eq.\(myID.uuidString.lowercased())"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ],
            as: [FriendRequestRow].self
        )
        guard !rows.isEmpty else { return [] }

        // 申请人的资料：**一次查完**，不要一个申请查一次 ——
        // 那又是"N 条申请 N 次请求"，和会话列表那里是同一个坑。
        let ids = rows.map { $0.fromId.uuidString.lowercased() }.joined(separator: ",")
        let profiles: [ProfileRow] = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(ids))"),
            ],
            as: [ProfileRow].self
        )
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return rows.compactMap { row in
            guard let profile = byID[row.fromId] else { return nil }
            return FriendRequest(id: row.id,
                                 fromID: row.fromId,
                                 fromName: profile.displayName,
                                 fromUsername: profile.username ?? "",
                                 fromAvatarURL: profile.avatarUrl.flatMap(URL.init(string:)),
                                 note: row.note,
                                 createdAt: row.createdAt)
        }
    }

    func respondToRequest(_ id: FriendRequest.ID, accept: Bool) async throws {
        do {
            let _: Bool = try await client.post(
                "/rest/v1/rpc/respond_friend_request",
                body: RespondRequestBody(requestId: id.uuidString.lowercased(), accept: accept),
                as: Bool.self
            )
        } catch {
            throw Self.translateRequestError(error)
        }
    }

    /// 翻译"申请"相关的报错。认不出来就**原样端上去**（不再吞掉）。
    private static func translateRequestError(_ error: Error) -> Error {
        guard case SupabaseError.http(_, let message) = error else { return error }
        if message.contains("没有这个人") { return ChatError.usernameNotFound }
        if message.contains("不能加自己") { return ChatError.cannotAddSelf }
        if message.contains("已经是好友") { return ChatError.alreadyFriends("你们已经是好友了。") }
        return ChatError.unknown(message)
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

    /// 拉一段对话的历史消息。
    ///
    /// `isGroup` 决定按哪种方式过滤 —— 两种不能混：
    ///   一对一 → 「我发给他的」或者「他发给我的」（recipient_id 配对）
    ///   群聊   → conversation_id 等于这个群
    ///
    /// ⚠️ 群消息的 recipient_id 是空的，用配对过滤**一条都查不到** ——
    ///    不分开写的话，群聊点进去是一片空白，而且不报任何错。
    /// 建群。
    ///
    /// 走服务器上的 create_group 函数，而不是客户端发三次请求 ——
    /// 中间失败会留下一个**没有成员的对话**（谁也看不见、也删不掉），
    /// 而且客户端可以跳过"创建者必须是群主"这一步。
    ///
    /// 函数返回的是新群的 id。它同时也是一段会话的 id ——
    /// 本地模型里 friendID 就是"哪段对话"，两边是同一个值。
    /// 把错误变成一句能看的话。日志里要能看出是哪一类问题。
    private func describeLoadError(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return String(describing: error)
    }

    /// 拉一个群的成员。
    ///
    /// 和好友列表同一个套路：**两步、两次请求**，而不是一个人一次 ——
    /// 群里 30 个人就是 30 次请求，列表一滚动就会转圈。
    func loadMembers(of conversationID: UUID) async throws -> [GroupMember] {
        struct MemberRow: Decodable { let userId: UUID }
        let members: [MemberRow] = try await client.get(
            "/rest/v1/conversation_members",
            query: [
                URLQueryItem(name: "select", value: "user_id"),
                URLQueryItem(name: "conversation_id",
                             value: "eq.\(conversationID.uuidString.lowercased())"),
            ],
            as: [MemberRow].self
        )
        guard !members.isEmpty else { return [] }

        let ids = members.map { $0.userId.uuidString.lowercased() }.joined(separator: ",")
        let profiles: [ProfileRow] = try await client.get(
            "/rest/v1/profiles",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(ids))"),
            ],
            as: [ProfileRow].self
        )

        return profiles.map {
            GroupMember(id: $0.id,
                        name: $0.displayName,
                        avatarSeed: $0.avatarSeed,
                        avatarURL: $0.avatarUrl.flatMap(URL.init(string:)))
        }
    }

    func createGroup(title: String, usernames: [String]) async throws -> UUID {
        struct Body: Encodable {
            let groupTitle: String
            let memberUsernames: [String]
        }
        // 函数签名是 group_title / member_usernames，
        // 编码器的 .convertToSnakeCase 会把上面两个属性转成那个样子。
        let body = Body(groupTitle: title, memberUsernames: usernames)

        // 服务器返回的是一段**裸 JSON 字符串**（`"a1b2..."` 这种），不是对象。
        // String 本身就是 Decodable，直接让它解就行 ——
        // 不需要去调客户端的私有方法手工处理字节。
        let text: String = try await client.post(
            "/rest/v1/rpc/create_group",
            body: body,
            as: String.self
        )
        guard let id = UUID(uuidString: text) else {
            throw ChatError.unknown("建群返回的内容看不懂：\(text.prefix(120))")
        }
        return id
    }

    func loadMessages(with friendID: Friend.ID, isGroup: Bool) async throws -> [Message] {
        guard let myID else { return [] }
        let me = myID.uuidString.lowercased()
        let other = friendID.uuidString.lowercased()

        // 群聊：直接按会话过滤，一行搞定
        // 一对一：PostgREST 的 or/and 可以嵌套，这是标准的"两人之间的消息"
        let filter = isGroup
            ? URLQueryItem(name: "conversation_id", value: "eq.\(other)")
            : URLQueryItem(name: "or",
                           value: "(and(sender_id.eq.\(me),recipient_id.eq.\(other)),"
                                + "and(sender_id.eq.\(other),recipient_id.eq.\(me)))")

        let rows: [MessageRow] = try await client.get(
            "/rest/v1/messages",
            query: [
                URLQueryItem(name: "select", value: "*"),
                filter,
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

    /// 发一条消息。
    ///
    /// `isGroup` 决定这条消息走哪条路：
    ///   一对一 → recipient_id 有值，conversation_id 为空
    ///   群聊   → recipient_id 为空，conversation_id 有值
    ///
    /// 数据库那边有约束钉着"不能两边都填 / 不能两边都空"，
    /// 所以这里填错了会当场报错，而不是留下一条归属不明的消息。
    func send(_ message: Message, isGroup: Bool) async throws -> Message {
        guard let myID else { throw ChatError.network }

        let payload = NewMessageRow(
            id: message.id,
            senderId: myID,
            recipientId: isGroup ? nil : message.friendID,
            conversationId: isGroup ? message.friendID : nil,
            body: message.text,
            imageUrl: message.imageURL?.absoluteString,
            audioUrl: message.audioURL?.absoluteString,
            audioSeconds: message.audioSeconds,
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
                body: UsernameBody(name: name),
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

        return Friend(id: profile.id,
                      name: profile.displayName,
                      avatarSeed: profile.avatarSeed,
                      avatarURL: profile.avatarUrl.flatMap(URL.init(string:)))
    }

    /// 把数据库函数抛出的错误翻成人话。
    /// 数据库函数里用的是 `raise exception '没有这个人'`，所以文案本来就是中文。
    private static func translateAddFriend(_ error: Error) -> Error {
        guard case SupabaseError.http(_, let message) = error else { return error }
        if message.contains("没有这个人") { return ChatError.usernameNotFound }
        if message.contains("不能加自己") { return ChatError.cannotAddSelf }

        // ⚠️ 认不出来就**把服务器的话原样端上去**，绝不吞成"请稍后再试"。
        //
        // 我这次就是被那句吞掉的：服务器明明说的是
        // "Could not find the function public.add_friend_by_username(username)"
        // —— 一眼就能看出是参数名不对。结果用户只看到「请稍后再试」，
        // 我也只能靠猜，白绕了一大圈。
        //
        // 原则：**翻译不出来的时候，宁可显示难懂的原文，
        // 也不要显示一句好听但没信息的话。**
        return ChatError.unknown(message)
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
    /// 一对一的收件人。**群消息这里是空的** —— 所以必须是可选。
    let recipientId: UUID?
    /// 群消息属于哪段对话。一对一为空。
    let conversationId: UUID?
    let body: String
    let imageUrl: String?
    let audioUrl: String?
    let audioSeconds: Double?
    let polishedWith: String?
    let createdAt: Date

    /// 这条消息属于哪段对话 —— 也就是本地模型里的 friendID。
    ///
    /// 一对一：对方是谁
    /// 群聊：conversation_id（群消息没有"对方"这个概念，只有"哪段对话"）
    func otherParty(myID: UUID) -> UUID? {
        if let conversationId { return conversationId }
        guard let recipientId else { return nil }
        return senderId == myID ? recipientId : senderId
    }

    func asMessage(myID: UUID) -> Message {
        let mine = senderId == myID
        // otherParty 现在可能为空（数据异常时）。用 senderId 兜底 ——
        // 宁可把消息挂在"发件人"上，也不要因为一条脏数据整批解码失败。
        return Message(
            id: id,
            friendID: otherParty(myID: myID) ?? senderId,
            text: body,
            imageURL: imageUrl.flatMap(URL.init(string:)),
            audioURL: audioUrl.flatMap(URL.init(string:)),
            audioSeconds: audioSeconds,
            senderID: senderId,
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
    /// 一对一填这个，群聊为 nil
    let recipientId: UUID?
    /// 群聊填这个，一对一为 nil
    let conversationId: UUID?
    let body: String
    let imageUrl: String?
    let audioUrl: String?
    let audioSeconds: Double?
    let polishedWith: String?
}

/// 加好友时发给数据库函数的参数。
/// 键名必须和函数签名里的参数名一致（`username`）。
/// 发好友申请。
///
/// ⚠️ **键名必须和数据库函数的参数名一字不差。**
/// 函数签名是 `send_friend_request(target_username text, note text)`，
/// 所以这里显式写出 CodingKeys —— **不依赖编码器的命名转换策略**。
/// 上次加好友失败就是因为这个（发成了 username，服务器找不到函数）。
private struct SendRequestBody: Encodable {
    let targetUsername: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case targetUsername = "target_username"
        case note
    }
}

/// 同意 / 拒绝。函数签名是 `respond_friend_request(request_id uuid, accept boolean)`。
private struct RespondRequestBody: Encodable {
    let requestId: String
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case accept
    }
}

/// 申请表的行
private struct FriendRequestRow: Decodable {
    let id: UUID
    let fromId: UUID
    let note: String?
    let createdAt: Date
}

/// 只传一个目标 id 的请求体（删好友用）。
private struct TargetBody: Encodable {
    let target: String
}

/// 加好友时发给数据库函数的参数。
///
/// ⚠️ **键名必须和数据库函数的参数名一字不差。**
///
/// 数据库那边的签名是 `add_friend_by_username(name text)` —— 参数叫 `name`。
/// 我原来这里写的是 `username`，于是 PostgREST 找不到匹配的函数，
/// 回了一句「没有这个函数」，而它又被下面的错误翻译吞成了「请稍后再试」。
/// 表现是"加好友全部失败"，查了半天才看到是这一行。
private struct UsernameBody: Encodable {
    let name: String
}
