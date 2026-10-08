import Foundation

// ============================================================================
// 用哪套服务 —— 整个"从演示变成真的"的开关
// ============================================================================
//
// 【它解决的问题】
//
// 从第一轮开始，聊天、AI、登录背后都是"假电"（演示数据）。
// 但你不可能在注册完 Supabase 的那天，让我把几十个文件全改一遍 ——
// 那既慢又容易出错。
//
// 所以做成一个开关：
//   · 没有配置服务器  → 假数据（演示模式，界面上有明确标识）
//   · 配置了服务器    → 真服务器
//
// **不用改任何界面代码，也不用改调用方。** 你只要把 Secrets.plist 填好。
//
// ============================================================================

enum AppServices {

    /// 有没有配置真服务器
    static var isConfigured: Bool { SupabaseConfig.current != nil }

    /// 登录和聊天**共用同一个客户端**。
    ///
    /// 为什么必须共用：登录成功后拿到的凭证（access token）要存在客户端里，
    /// 之后每个请求都得带上它 —— 服务器就是靠这个知道"你是谁"、
    /// 才能判断"这条消息该不该给你看"。两个客户端各存一份就会对不上。
    private static let client: SupabaseClient? = {
        guard let config = SupabaseConfig.current else {
            AppLog.info(.network, "没有配置服务器，使用演示数据")
            return nil
        }
        AppLog.info(.network, "使用真服务器：\(config.debugDescription)")
        return SupabaseClient(config: config)
    }()

    static func makeAuthService() -> AuthService {
        guard let client else { return MockAuthService() }
        return SupabaseAuthService(client: client)
    }

    static func makeAIService() -> AIService {
        guard let client else { return MockAIService() }
        return SupabaseAIService(client: client)
    }

    static func makeChatService() -> ChatService {
        guard let client else { return MockChatService() }
        return SupabaseChatService(client: client)
    }
}
