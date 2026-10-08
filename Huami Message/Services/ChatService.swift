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

    /// 拉取会话列表（消息首页要显示的那些行）
    func loadConversations() async throws -> [Conversation]

    /// 拉取和某个好友的历史消息
    func loadMessages(with friendID: Friend.ID) async throws -> [Message]

    /// 把一条消息发出去。
    /// 参数是已经组装好的 Message，返回服务器「确认收到」后的版本
    /// （真后端会在这里补上服务器生成的时间和编号）。
    func send(_ message: Message) async throws -> Message

    /// 服务器「推」过来的新消息 —— 也就是实时收消息。
    ///
    /// 现在假数据里用它模拟「好友隔几秒回你一句」，
    /// 以后换成 Supabase 的实时通道，界面的处理方式完全一样。
    ///
    /// 用 AsyncStream 的好处：界面只管「一条条地收」，
    /// 完全不用管底下是 WebSocket、长轮询还是别的什么。
    func incomingMessages() -> AsyncStream<Message>
}
