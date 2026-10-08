import Foundation

// ============================================================================
// 真·AI 服务（走 Supabase 云函数中转）
// ============================================================================
//
// 【为什么不直接连 DeepSeek】
//
// 因为那需要把 API Key 写进 App。App 装到手机上就是一个压缩包，
// 任何人解开来都能看到里面的字符串。Key 一旦泄露，
// 别人会拿它刷 token，**账单是你的**。
//
// 所以走云函数：App 只认识云函数的网址，Key 存在服务器的环境变量里。
//
// 【它和假实现说的是同一套话】
//
// 云函数推回来的事件形状，和 `MockAIService` 造出来的一模一样：
//   {type:"status"}  一句状态提示
//   {type:"block"}   一个决策方块
//   {type:"recommendation"}  最后的建议
//   {type:"text"}    一整段文字（润色用）
//   {type:"done"}    结束
//
// 所以换实现的时候，界面一行都没动。
//
// ============================================================================

final class SupabaseAIService: AIService {

    private let client: SupabaseClient

    /// 真 AI —— 「演示模式」的提示会自动消失
    let isDemoData = false

    /// 云函数的路径（Supabase 的函数都挂在这个前缀下面）
    private static let functionPath = "/functions/v1/ai-proxy"

    init(client: SupabaseClient) {
        self.client = client
    }

    // ========================================================================
    // 模块一：润色一句话
    // ========================================================================

    func polish(_ text: String, style: PolishStyle) -> AsyncThrowingStream<String, Error> {
        let request = ProxyRequest(
            mode: "polish",
            text: text,
            style: style.rawValue,
            friendName: nil,
            intent: nil,
            messages: nil
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self.events(for: request) {
                        if case .text(let value) = event {
                            continuation.yield(value)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // ========================================================================
    // 模块二：小助手看一段对话
    // ========================================================================

    func advise(context: AssistantContext,
                intent: AssistantIntent) -> AsyncThrowingStream<AssistantEvent, Error> {
        let request = ProxyRequest(
            mode: "advise",
            text: nil,
            style: nil,
            friendName: context.friendName,
            intent: intent.rawValue,
            // 只发最近若干条 —— 这是对用户的隐私承诺，不能只是说说
            messages: context.messages.map {
                ProxyMessage(mine: $0.sender == .me, text: $0.text)
            }
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in self.events(for: request) {
                        switch event {
                        case .status(let value):         continuation.yield(.status(value))
                        case .block(let block):          continuation.yield(.block(block))
                        case .recommendation(let value): continuation.yield(.recommendation(value))
                        case .text, .done:               break   // 这两个不属于助手
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // ========================================================================
    // 内部：把云函数的事件流读出来
    // ========================================================================

    private enum Event {
        case status(String)
        case block(DecisionBlock)
        case recommendation(String)
        case text(String)
        case done
    }

    private func events(for request: ProxyRequest) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lines = try await client.streamLines(Self.functionPath, body: request)
                    for try await line in lines {
                        if Task.isCancelled { break }
                        guard let event = Self.parse(line) else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 解析一行 SSE。
    ///
    /// 服务器发出来的是这样：
    ///     data: {"type":"block","value":{...}}
    ///     （空行）
    ///
    /// 所以：认 `data:` 前缀 → 去掉前缀 → 当 JSON 解析。
    /// 解析不了的直接跳过 —— 服务器偶尔发个心跳之类不该让整条流崩掉。
    private static func parse(_ line: String) -> Event? {
        guard line.hasPrefix("data:") else { return nil }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        switch type {
        case "status":
            guard let value = object["value"] as? String else { return nil }
            return .status(value)

        case "recommendation":
            guard let value = object["value"] as? String else { return nil }
            return .recommendation(value)

        case "text":
            guard let value = object["value"] as? String else { return nil }
            return .text(value)

        case "block":
            // 方块的结构直接复用客户端的解码器 ——
            // 这样"服务器给的字段名"和"客户端认识的字段名"永远只有一处定义
            guard let value = object["value"],
                  let blockData = try? JSONSerialization.data(withJSONObject: value),
                  let block = try? SupabaseClient.jsonDecoder.decode(DecisionBlock.self, from: blockData)
            else {
                AppLog.error(.ai, "收到一个看不懂的方块：\(payload.prefix(200))")
                return nil
            }
            return .block(block)

        case "done":
            return .done

        default:
            return nil
        }
    }
}

// ============================================================================
// 发给云函数的数据形状
// ============================================================================

private struct ProxyRequest: Encodable {
    let mode: String
    let text: String?
    let style: String?
    let friendName: String?
    let intent: String?
    let messages: [ProxyMessage]?
}

private struct ProxyMessage: Encodable {
    /// true = 我发的
    let mine: Bool
    let text: String
}
