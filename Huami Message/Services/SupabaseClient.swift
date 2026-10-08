import Foundation

// ============================================================================
// 跟 Supabase 说话的底层
// ============================================================================
//
// 【为什么不用官方的 supabase-swift】
//
// 算过一笔账：
//   · 官方 SDK 要加一个 SPM 依赖，会拉下来几十个包、几百 MB
//   · 而我们其实只用到两件事：一个 REST 接口（GET/POST）和一个 WebSocket
//   · 自己写这一层还能顺便把错误信息翻成人话 —— 出问题时好查得多
//
// 代价是"官方的便利功能"要自己写（比如自动刷新 token）。
// 第一版用不上，需要的时候再加。
//
// ============================================================================

/// 一个很薄的 HTTP 客户端。只负责：拼 URL、加请求头、解析错误。
///
/// 登录和聊天两个服务**共用同一个实例**，因为它们要共享登录凭证
/// （access token 存在这里，登录成功后设置一次，之后所有请求自动带上）。
final class SupabaseClient {

    let config: SupabaseConfig

    private let session: URLSession

    /// 登录后拿到的凭证。nil 表示还没登录（这时用 anon key，只能访问公开的东西）。
    private(set) var accessToken: String?

    /// 当前登录用户的 id。
    ///
    /// 【为什么放在这里，而不是让聊天服务自己去找】
    ///
    /// 聊天服务必须知道"我是谁" —— 比如查消息时要表达
    /// "发给我或我发出的"。但它天生拿不到这个信息：
    /// ChatStore 是在 App 启动时就建好的，那时候还没登录。
    ///
    /// 而登录和聊天**共用同一个客户端实例**（这样凭证才能自动带上），
    /// 所以让登录服务在登录成功时顺手写在这里，聊天服务用的时候直接读 ——
    /// 既不用改架构，也不用把用户 id 一层层传下去。
    private(set) var currentUserID: UUID?

    init(config: SupabaseConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        // 15 秒还没响应就放弃。
        // 不设的话默认是 60 秒，用户会觉得 App 卡死了。
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
    }

    /// 登录成功 / 退出登录时调用。凭证和身份必须**一起**更新 ——
    /// 只换凭证不换身份，会出现"用新账号的钥匙开旧账号的门"这种怪事。
    func setSession(accessToken: String?, userID: UUID?) {
        self.accessToken = accessToken
        self.currentUserID = userID
    }

    // MARK: - 对外的方法

    func get<T: Decodable>(_ path: String,
                           query: [URLQueryItem] = [],
                           as type: T.Type) async throws -> T {
        let data = try await perform(.get, path: path, query: query, body: nil, prefer: nil)
        return try Self.decode(data, as: type)
    }

    @discardableResult
    func post<Body: Encodable, T: Decodable>(_ path: String,
                                             query: [URLQueryItem] = [],
                                             body: Body,
                                             prefer: String? = nil,
                                             as type: T.Type) async throws -> T {
        let payload = try Self.encode(body)
        let data = try await perform(.post, path: path, query: query, body: payload, prefer: prefer)
        return try Self.decode(data, as: type)
    }

    /// 改已有的数据（PostgREST 的 PATCH）。
    /// 配 `Prefer: return=representation` 能把改完之后的那一行拿回来。
    @discardableResult
    func patch<Body: Encodable, T: Decodable>(_ path: String,
                                              query: [URLQueryItem] = [],
                                              body: Body,
                                              prefer: String? = nil,
                                              as type: T.Type) async throws -> T {
        let payload = try Self.encode(body)
        let data = try await perform(.patch, path: path, query: query, body: payload, prefer: prefer)
        return try Self.decode(data, as: type)
    }

    /// 不关心返回内容的 POST
    func post<Body: Encodable>(_ path: String,
                               query: [URLQueryItem] = [],
                               body: Body,
                               prefer: String? = nil) async throws {
        let payload = try Self.encode(body)
        _ = try await perform(.post, path: path, query: query, body: payload, prefer: prefer)
    }

    /// 发一个请求，然后把响应**当成一行一行的流**读出来。
    ///
    /// 专门给"服务器一边算一边往回吐"的接口用（SSE，Server-Sent Events）。
    /// 普通请求要等整个响应回来，而这种要**边到边处理** ——
    /// 不然"打字机效果"就只能靠客户端假装，那是骗人的。
    ///
    /// `URLSession.bytes(for:)` 给的正是这种能力：一个可以逐行消费的字节流。
    /// 流式 POST。
    ///
    /// `headers` 是给调用方加自定义头用的 —— 目前只有一个用途：
    /// AI 服务要把**用户自己填的密钥**带上去（见 `PersonalAIKey`）。
    /// 放在这里而不是写死，是因为密钥是"每个用户不一样"的东西，
    /// 不该混进客户端的通用逻辑里。
    func streamLines<Body: Encodable>(_ path: String,
                                      body: Body,
                                      headers: [String: String] = [:]) async throws -> AsyncThrowingStream<String, Error> {
        var request = URLRequest(url: config.endpoint(path))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try Self.encode(body)
        // 流式请求不能设太短的超时 —— 模型思考本来就要几秒
        request.timeoutInterval = 60

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            if (error as? URLError)?.code == .cancelled { throw SupabaseError.cancelled }
            AppLog.error(.network, "POST \(path) 流式请求失败：\(error.localizedDescription)")
            throw SupabaseError.network
        }

        guard let http = response as? HTTPURLResponse else { throw SupabaseError.network }

        guard (200..<300).contains(http.statusCode) else {
            // 失败时响应体不是流式的事件，而是一小段 JSON 错误
            var text = ""
            for try await line in bytes.lines { text += line }
            let message = Self.extractMessage(from: Data(text.utf8))
            AppLog.error(.network, "POST \(path) → \(http.statusCode)：\(message)")
            throw SupabaseError.http(status: http.statusCode, message: message)
        }

        AppLog.info(.network, "POST \(path) → \(http.statusCode)（流式）")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: SupabaseError.network)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    // MARK: - 真正发请求

    private func perform(_ method: Method,
                         path: String,
                         query: [URLQueryItem],
                         body: Data?,
                         prefer: String?) async throws -> Data {

        var components = URLComponents(url: config.endpoint(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw SupabaseError.badURL(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        // anon key 放在 apikey 头里 —— 这是 Supabase 认人的方式
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        // 登录之后换成用户的 token，服务器的权限规则（RLS）才会按"我是谁"来判
        request.setValue("Bearer \(accessToken ?? config.anonKey)",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // ⚠️ **取消不是网络故障，必须分开处理。**
            //
            // URLSession 把"任务被取消"也当成错误抛出来（URLError.cancelled）。
            // 如果不区分，日志里会写"连不上服务器"，而其实是自己取消的 ——
            // 这种误导性日志会让人往完全错误的方向排查。
            // （我这次就被它骗了一下：以为是服务器的问题。）
            if (error as? URLError)?.code == .cancelled {
                AppLog.info(.network, "\(method.rawValue) \(path) 已取消")
                throw SupabaseError.cancelled
            }
            // 只记路径和方法，**不记完整 URL**
            //（虽然 anon key 不在 URL 里，但养成"日志里不出现凭证"的习惯没坏处）
            AppLog.error(.network, "\(method.rawValue) \(path) 网络失败：\(error.localizedDescription)")
            throw SupabaseError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.network
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractMessage(from: data)
            AppLog.error(.network, "\(method.rawValue) \(path) → \(http.statusCode)：\(message)")
            throw SupabaseError.http(status: http.statusCode, message: message)
        }

        AppLog.info(.network, "\(method.rawValue) \(path) → \(http.statusCode)")
        return data
    }

    // MARK: - 编码解码

    private static func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try jsonEncoder.encode(body)
        } catch {
            throw SupabaseError.encoding(String(describing: error))
        }
    }

    private static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        // 204 / 空响应对应"成功但没有内容"。
        // 如果 T 是 EmptyResponse 就直接返回，否则交给下面报解码错误。
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            // 把原始返回的前 300 个字符带上 —— 不然只看到
            // "keyNotFound(CodingKeys(...))" 根本不知道服务器到底返回了什么
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "(二进制)"
            AppLog.error(.network, "解码失败：\(error)\n返回内容：\(preview)")
            throw SupabaseError.decoding(preview)
        }
    }

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = SupabaseDate.parse(text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "看不懂的时间格式：\(text)")
                )
            }
            return date
        }
        return decoder
    }()

    /// 从错误响应里挖出一句能看的话。
    ///
    /// 为什么要循环找好几个字段：Supabase 不同的接口用的字段名不一样 ——
    /// 登录接口用 `msg` / `error_description`，数据库接口用 `message` / `hint`。
    private static func extractMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "message", "error_description", "error", "hint", "details"] {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
        }
        let text = String(data: data.prefix(200), encoding: .utf8) ?? ""
        return text.isEmpty ? "服务器没有说明原因" : text
    }
}

/// "成功但不需要返回内容"时用的占位类型
struct EmptyResponse: Decodable {}

// ============================================================================
// 错误
// ============================================================================

enum SupabaseError: LocalizedError {

    case badURL(String)
    case cancelled
    case network
    case http(status: Int, message: String)
    case encoding(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let path):
            "内部错误：网址拼错了（\(path)）"

        case .cancelled:
            "请求已取消。"
        case .network:
            "连不上服务器。检查一下网络，或者稍后再试。"

        case .encoding(let detail):
            "内部错误：数据打包失败（\(detail)）"

        case .decoding(let preview):
            "服务器返回了看不懂的内容。\n\n\(preview)"

        case .http(let status, let message):
            // 把常见的状态码翻成人话。
            // 用户看到 "Error 422" 只会一脸问号，看到"这个邮箱已经注册过了"才知道该干嘛。
            switch status {
            case 400, 422:
                message.isEmpty ? "这个操作服务器不接受，检查一下填的内容。" : message
            case 401, 403:
                "登录状态失效了，请重新登录。"
            case 404:
                "服务器上找不到这个接口。可能是数据库还没建好（schema.sql 跑了吗？）。"
            case 409:
                "已经存在了，不用重复操作。"
            case 429:
                "操作太频繁，等一分钟再试。"
            case 500...599:
                // ⚠️ **必须带上服务器的原话。**
                //
                // 500 不代表"服务器挂了"这么笼统 —— Supabase 很多时候是在
                // 说具体的事，比如 "Error sending confirmation email"
                //（发确认邮件失败，多半是 SMTP 配置或发信域名的问题）。
                //
                // 我原来把它统一成"服务器出错了，稍后再试"，
                // 等于把唯一的线索删掉了。
                message.isEmpty ? "服务器出错了，稍后再试。" : "服务器出错了：\(message)"
            default:
                "出错了（\(status)）：\(message)"
            }
        }
    }
}

// ============================================================================
// 时间解析
// ============================================================================

/// Supabase 返回的时间是 ISO8601，但**有的带小数秒、有的不带** ——
/// 比如 `2026-10-08T12:34:56.789+00:00` 和 `2026-10-08T12:34:56+00:00`。
///
/// `JSONDecoder.DateDecodingStrategy.iso8601` 只认后者，所以必须自己写一个两种都试。
/// 这个坑不踩一次很难想到。
enum SupabaseDate {

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        // ⚠️ Postgres 的时间戳带**微秒**（6 位小数），
        //    而 ISO8601DateFormatter 只认 3 位（毫秒）。
        //    多出来的位数会让它**直接解析失败** —— 而且返回的字符串
        //    看起来完全正常（2026-10-08T12:34:56.789123+00:00），
        //    不实测根本想不到问题出在这里。
        let normalized = normalizeFraction(text)
        return withFraction.date(from: normalized) ?? plain.date(from: normalized)
    }

    /// 把小数秒截到 3 位
    private static func normalizeFraction(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }

        let digitsStart = text.index(after: dot)
        var digitsEnd = digitsStart
        while digitsEnd < text.endIndex, text[digitsEnd].isNumber {
            digitsEnd = text.index(after: digitsEnd)
        }

        let count = text.distance(from: digitsStart, to: digitsEnd)
        guard count > 3 else { return text }

        let cut = text.index(digitsStart, offsetBy: 3)
        return String(text[text.startIndex..<cut]) + String(text[digitsEnd...])
    }
}
