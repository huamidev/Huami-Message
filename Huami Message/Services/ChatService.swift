import Foundation

/// 【全项目最重要的一道防火墙】
///
/// 界面（View）永远只跟这个「协议」说话，永远不知道数据是从哪来的。
/// 现在背后是假数据（MockChatService）；
/// 第一步之后会换成真服务器（SupabaseChatService）。
///
/// 换的时候，所有界面代码一行都不用改。
///
/// 这就是「先做界面、后接后端」能成立的原因，
/// 也是我建议你先做第 0 步、而不是一上来就搭后端的底气。
///
/// 打个比方：这份协议就像墙上的插座标准。
/// 今天插的是「假电」（调试电源），明天换成「真电」（市电），
/// 墙上的插孔形状不变，所以你的电器（界面）不用改。
protocol ChatService {

    /// 当前用的是不是**假数据**。
    ///
    /// 为什么需要它：接上真服务器之前，App 里会有几个假好友（林一、妈妈……）。
    /// 朋友通过 TestFlight 装上去会一脸问号，甚至以为 App 坏了。
    /// 所以界面上要明说"这是演示数据"。
    ///
    /// 接上 Supabase 之后，那边的实现返回 false，这个标识就自动消失了 ——
    /// 不用记得去删代码。
    var isDemoData: Bool { get }

    /// 拉取会话列表（消息首页要显示的那些行）
    func loadConversations() async throws -> [Conversation]

    /// 拉取和某个好友的历史消息
    func loadMessages(with friendID: Friend.ID, isGroup: Bool) async throws -> [Message]

    /// 建一个群。返回新群的 id（也就是它的"会话 id"）。
    /// 服务器那边一次做完：建对话 + 把我设成群主 + 把这些人拉进来。
    func createGroup(title: String, usernames: [String]) async throws -> UUID

    /// 把一条消息发出去。
    /// 参数是已经组装好的 Message，返回服务器「确认收到」后的版本
    /// （真后端会在这里补上服务器生成的时间和编号）。
    /// 发一条消息。`isGroup` 决定走一对一还是群聊那条路。
    func send(_ message: Message, isGroup: Bool) async throws -> Message

    /// 服务器「推」过来的新消息 —— 也就是实时收消息。
    ///
    /// 现在假数据里用它模拟「好友隔几秒回你一句」，
    /// 以后换成 Supabase 的实时通道，界面的处理方式完全一样。
    ///
    /// 用 AsyncStream 的好处：界面只管「一条条地收」，
    /// 完全不用管底下是 WebSocket、长轮询还是别的什么。
    func incomingMessages() -> AsyncStream<Message>

    /// 用用户名加一个好友，返回加上的那个人。
    ///
    /// 【为什么用用户名，而不是读通讯录】
    ///
    /// 读通讯录要申请权限，用户看到"这个 App 想访问你的通讯录"就直接卸载了；
    /// 而且那等于把用户的关系网整个上传，是个很重的隐私承诺。
    ///
    /// 用户名是公开的：**任何人都能加你**（用户已确认接受这一点）。
    func addFriend(username: String) async throws -> Friend

    /// 按用户名找一个人（用来先看他的主页，再决定加不加）。
    func findProfile(username: String) async throws -> ProfileSummary

    /// 发一条好友申请。
    ///
    /// 注意它**不会**立刻成为好友 —— 要等对方同意。
    /// （以前是直接加上的，那等于任何人都能往你的好友列表里塞自己。）
    func sendFriendRequest(username: String, note: String?) async throws

    /// 拉"发给我的、还没处理的"申请。
    func loadIncomingRequests() async throws -> [FriendRequest]

    /// 同意或拒绝一条申请。
    func respondToRequest(_ id: FriendRequest.ID, accept: Bool) async throws

    /// 删除好友（**双向**：两边都解除）。
    ///
    /// 注意它和「删除聊天记录」是两件事：
    ///   · 删除聊天 = 只清我本地的记录，还是好友
    ///   · 删除好友 = 解除关系，两边都不再是好友
    func removeFriend(_ id: Friend.ID) async throws
}

// MARK: - 加好友会出的错

/// 加好友相关的错误。
///
/// 和 `AuthError` 一样，每种错误自带一句能给用户看的人话 ——
/// 界面直接显示 `errorDescription` 就行，不用在视图里写一堆 if-else 翻译错误码。
enum ChatError: LocalizedError, Equatable {

    case usernameNotFound
    case requestAlreadyPending
    case alreadyFriends(String)
    case cannotAddSelf
    case network
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .requestAlreadyPending:
            "你已经发过申请了，等对方处理。"

        case .usernameNotFound:
            "没找到这个人。检查一下用户名有没有输错？"
        case .alreadyFriends(let name):
            "\(name)已经在你的好友列表里了。"
        case .cannotAddSelf:
            "这是你自己的用户名。"
        case .network:
            "网络好像不太顺，等一下再试。"
        case .unknown(let message):
            message
        }
    }
}
