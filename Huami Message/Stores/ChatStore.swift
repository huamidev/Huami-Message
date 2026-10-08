import SwiftUI

/// 消息模块的「总管家」。
///
/// 界面只做两件事：**读它里面的数据、调它的方法**。
/// 界面完全不关心数据是本地假的还是从服务器来的 —— 那是 ChatService 的事。
///
/// @Observable 是苹果现在的标准写法：数据一变，用到它的界面自动刷新。
/// 你不用手写任何「通知界面更新」的代码，这是 SwiftUI 相对 UIKit 最大的省事之处。
@Observable
final class ChatStore {

    // MARK: - 界面要读的数据

    private(set) var conversations: [Conversation] = []

    /// 每个好友对应的消息列表。
    /// 用字典按好友分开存，切换会话时不用重新拉，进出都是瞬间的。
    private(set) var messagesByFriend: [Friend.ID: [Message]] = [:]

    /// 首次加载中（界面用它决定要不要显示转圈）
    private(set) var isLoading = false

    // MARK: - 内部

    private let service: ChatService
    private var listenTask: Task<Void, Never>?

    init(service: ChatService = MockChatService()) {
        self.service = service
    }

    // MARK: - 读

    /// 取某个好友的消息（界面用）
    func messages(with friendID: Friend.ID) -> [Message] {
        messagesByFriend[friendID] ?? []
    }

    // MARK: - 启动

    /// App 启动时调一次：拉会话列表、拉历史消息、开始监听新消息。
    ///
    /// 【第 1 步这里会被改写，先说明白，免得以后你觉得我在返工】
    /// 接上真 Supabase 之后，这个方法的顺序会变成：
    ///   ① 先从**本地数据库**读出来 → 界面立刻有内容（瞬间可用，不等网络）
    ///   ② 再在后台悄悄去服务器拉增量 → 拉到什么补什么
    /// 现在假数据没有「本地/远端」之分，所以看起来是一步到位。
    /// 但界面的写法和这个「先本地后网络」的原则是兼容的，不用改。
    func start() async {
        guard conversations.isEmpty else { return }
        isLoading = true

        do {
            conversations = try await service.loadConversations()
            for convo in conversations {
                messagesByFriend[convo.friend.id] = try await service.loadMessages(with: convo.friend.id)
            }
        } catch {
            print("加载失败：", error)
        }

        isLoading = false
        listen()
    }

    // MARK: - 发送

    func send(_ text: String, to friendID: Friend.ID, polishedWith: PolishStyle? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // ① 先在本地造一条消息并立刻显示。
        //    用户按下发送键的**那一瞬间**就看到它出现在列表里 —— 这一步完全不等网络。
        //    这就是「绝不阻塞界面」的具体做法，也是 Telegram 那种手感的真正来源：
        //    不是动画快，而是**从来不花时间等服务器**。
        let local = Message(friendID: friendID, text: trimmed, sender: .me, polishedWith: polishedWith)
        messagesByFriend[friendID, default: []].append(local)
        touch(friendID: friendID, last: trimmed, at: local.sentAt)

        // ② 再去真正发给服务器（现在服务是假的，所以只是走个过场）。
        do {
            let confirmed = try await service.send(local)
            // 服务器确认后，用它返回的版本替换本地那条。
            // 因为 id 保持不变，界面不会闪、不会跳。
            replace(local.id, in: friendID, with: confirmed)
        } catch {
            // 接上真后端后，这里不该是 print，而是给那条消息打一个
            // 「发送失败 · 点此重试」的标记。第 1 步会补上。
            print("发送失败：", error)
        }
    }

    // MARK: - 未读

    /// 进入某个会话时清掉未读小红点
    func markRead(_ friendID: Friend.ID) {
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }
        conversations[index].unreadCount = 0
    }

    // MARK: - 收消息

    /// 开始监听服务器推来的新消息。
    /// 这是「对方发消息给我，界面自动冒出来」的实现。
    private func listen() {
        guard listenTask == nil else { return }
        let service = self.service
        listenTask = Task { [weak self] in
            for await message in service.incomingMessages() {
                self?.receive(message)
            }
        }
    }

    private func receive(_ message: Message) {
        // 去重：同一条消息只存一次（网络偶尔会重复推送，这是必须防的）
        let existing = messagesByFriend[message.friendID] ?? []
        guard !existing.contains(where: { $0.id == message.id }) else { return }

        messagesByFriend[message.friendID, default: []].append(message)
        touch(friendID: message.friendID, last: message.text, at: message.sentAt, increaseUnread: true)
    }

    // MARK: - 辅助

    /// 替换掉本地那条「发送中」的消息
    private func replace(_ id: Message.ID, in friendID: Friend.ID, with message: Message) {
        guard let index = messagesByFriend[friendID]?.firstIndex(where: { $0.id == id }) else { return }
        messagesByFriend[friendID]?[index] = message
    }

    /// 更新会话列表里那一行的摘要、时间、未读数，并把它顶到最前面
    private func touch(friendID: Friend.ID, last: String, at date: Date, increaseUnread: Bool = false) {
        guard let index = conversations.firstIndex(where: { $0.friend.id == friendID }) else { return }

        conversations[index].lastMessage = last
        conversations[index].lastTime = date
        if increaseUnread { conversations[index].unreadCount += 1 }

        // 最近说话的会话排到第一位 —— 聊天 App 的基本预期
        let convo = conversations.remove(at: index)
        conversations.insert(convo, at: 0)
    }
}
