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

    /// 检查服务器有没有配置好（建表、关邮箱验证、部署云函数）。
    /// 演示模式下永远返回空 —— 没连服务器，就没什么可检查的。
    static func runServerDiagnostics() async -> [ServerIssue] {
        guard let client else { return [] }
        return await ServerDiagnostics.check(client)
    }

    static func makeAuthService() -> AuthService {
        guard let client else { return MockAuthService() }
        return SupabaseAuthService(client: client)
    }

    static func makeAIService() -> AIService {
        guard let client else { return MockAIService() }
        return SupabaseAIService(client: client)
    }

    /// 传一张图片到聊天存储，返回可以直接显示的网址。
    ///
    /// 放在这里而不是加进 `ChatService` 协议：那是"聊天"的接口
    ///（发消息、拉历史），传文件是另一件事。混进去之后，
    /// 假实现也得假装能传文件，反而更绕。
    static func uploadChatImage(_ data: Data) async throws -> URL {
        guard let client else {
            throw SupabaseError.http(status: 503, message: "现在是示例模式，发不了图片。")
        }
        return try await client.upload(data, bucket: SupabaseClient.Bucket.chat,
                                       contentType: "image/jpeg")
    }

    /// 传一张头像，返回可以直接显示的网址。
    static func uploadAvatar(_ data: Data) async throws -> URL {
        guard let client else {
            throw SupabaseError.http(status: 503, message: "现在是示例模式，换不了头像。")
        }
        return try await client.upload(data, bucket: SupabaseClient.Bucket.avatar,
                                       contentType: "image/jpeg")
    }

    static func makeChatService() -> ChatService {
        guard let client else { return MockChatService() }
        return SupabaseChatService(client: client)
    }
}
