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

    init(config: SupabaseConfig) {
        self.config = config

        let configuration = URLSessionConfiguration.default
        // 15 秒还没响应就放弃。
        // 不设的话默认是 60 秒，用户会觉得 App 卡死了。
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
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

    /// 不关心返回内容的 POST
    func post<Body: Encodable>(_ path: String,
                               query: [URLQueryItem] = [],
                               body: Body,
                               prefer: String? = nil) async throws {
        let payload = try Self.encode(body)
        _ = try await perform(.post, path: path, query: query, body: payload, prefer: prefer)
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
            // 只记路径和方法，**不记完整 URL**（虽然 anon key 不在 URL 里，
            // 但养成"日志里不出现凭证"的习惯没坏处）
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
            return try encoder.encode(body)
        } catch {
            throw SupabaseError.encoding(String(describing: error))
        }
    }

    private static func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        // 204 / 空响应对应"成功但没有内容"。
        // 如果 T 是 EmptyResponse 就直接返回，否则交给下面报解码错误。
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // 把原始返回的前 300 个字符带上 —— 不然只看到
            // "keyNotFound(CodingKeys(...))" 根本不知道服务器到底返回了什么
            let preview = String(data: data.prefix(300), encoding: .utf8) ?? "(二进制)"
            AppLog.error(.network, "解码失败：\(error)\n返回内容：\(preview)")
            throw SupabaseError.decoding(preview)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
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
    case network
    case http(status: Int, message: String)
    case encoding(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let path):
            "内部错误：网址拼错了（\(path)）"

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
                "服务器出错了，稍后再试。"
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
        withFraction.date(from: text) ?? plain.date(from: text)
    }
}
