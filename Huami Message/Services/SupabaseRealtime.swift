import Foundation

// ============================================================================
// 实时收消息（Supabase Realtime）
// ============================================================================
//
// 【它解决什么】
//
// 没有它，App 就只能靠"每隔几秒去问一次服务器有没有新消息"。
// 那样既费电、费流量，消息还会延迟好几秒 ——
// 而"消息收发要像 Telegram 一样丝滑"是这个产品最优先的目标。
//
// 【它说的话是什么协议】
//
// Supabase 的实时推送底下是 Phoenix Channels，一套基于 WebSocket 的
// 发布订阅协议。用起来大概是三步：
//   ① 连上 ws://…/realtime/v1/websocket，带上 apikey
//   ② 发一条 "phx_join" 加入某个频道，说明我想听什么变化
//   ③ 之后服务器会把变化一条条推给我
//
// 【为什么自己要处理重连和心跳】
//
// WebSocket 是长连接，而长连接一定会断：切后台、换 Wi-Fi、地铁进隧道……
// 断了不重连的话，用户会以为"没人给我发消息"，其实只是连接掉了。
//
// 心跳是因为服务器 30 秒收不到任何东西就会主动断开。
//
// ============================================================================

final class SupabaseRealtime {

    private let config: SupabaseConfig
    private let accessToken: String?
    private let userID: UUID
    private let session: URLSession

    private var socket: URLSessionWebSocketTask?

    /// 主动停止的标志。用它区分"用户关掉了"和"网断了" ——
    /// 前者不该重连，后者必须重连。
    private var isStopped = false

    init(config: SupabaseConfig, accessToken: String?, userID: UUID) {
        self.config = config
        self.accessToken = accessToken
        self.userID = userID
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - 对外

    /// 源源不断地吐出"发给我的新消息"。
    /// 断线会自动重连；调用方取消这个流就彻底停掉。
    func records() -> AsyncStream<MessageRow> {
        AsyncStream { continuation in
            let task = Task { await self.run(continuation) }
            continuation.onTermination = { [weak self] _ in
                self?.isStopped = true
                task.cancel()
                self?.disconnect()
            }
        }
    }

    func disconnect() {
        isStopped = true
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - 主循环：连上 → 收 → 断了就退避重连

    private func run(_ continuation: AsyncStream<MessageRow>.Continuation) async {
        var attempt = 0

        while !Task.isCancelled && !isStopped {
            do {
                try await connectAndListen(continuation)
                attempt = 0   // 正常断开（比如服务端重启）不算失败，重连不要退避太久
            } catch {
                if Task.isCancelled || isStopped { break }
                AppLog.error(.network, "实时连接中断：\(error.localizedDescription)")
            }

            guard !Task.isCancelled && !isStopped else { break }

            // 退避重连：1 秒、2 秒、4 秒、8 秒……最多 30 秒。
            // 为什么要退避：服务端挂了的时候，如果客户端一秒重试一次，
            // 成千上万个客户端会一起把它压得更起不来（这叫惊群）。
            attempt += 1
            let seconds = min(30, pow(2.0, Double(attempt - 1)))
            AppLog.info(.network, "\(Int(seconds)) 秒后重连实时频道")
            try? await Task.sleep(for: .seconds(seconds))
        }

        continuation.finish()
    }

    private func connectAndListen(_ continuation: AsyncStream<MessageRow>.Continuation) async throws {
        guard let url = webSocketURL() else { throw SupabaseError.badURL("realtime") }

        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()

        try await join(socket)

        // 心跳。用 25 秒（服务器是 30 秒超时），留 5 秒余量 ——
        // 网络抖一下也不会被误判成"客户端死了"。
        let heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, let self, let socket = self.socket else { break }
                try? await self.sendFrame([
                    "topic": "phoenix",
                    "event": "heartbeat",
                    "payload": [:],
                    "ref": "hb",
                ], on: socket)
            }
        }
        defer { heartbeat.cancel() }

        while !Task.isCancelled && !isStopped {
            let frame = try await socket.receive()
            guard case .string(let text) = frame else { continue }
            handle(text, continuation)
        }
    }

    // MARK: - 拼地址

    private func webSocketURL() -> URL? {
        var components = URLComponents(
            url: config.endpoint("/realtime/v1/websocket"),
            resolvingAgainstBaseURL: false
        )
        // http → ws，https → wss。
        // 这一步是为了本机测试能连 http://127.0.0.1 —— 真服务器永远是 https。
        components?.scheme = (config.url.scheme == "http") ? "ws" : "wss"
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: config.anonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        return components?.url
    }

    // MARK: - 加入频道

    private func join(_ socket: URLSessionWebSocketTask) async throws {
        // 只需要"发给我的"那一条。自己发出去的消息本地已经立刻显示了，
        // 再从服务器收一遍反而会重复。
        let changes: [[String: Any]] = [[
            "event": "INSERT",
            "schema": "public",
            "table": "messages",
            "filter": "recipient_id=eq.\(userID.uuidString.lowercased())",
        ]]

        try await sendFrame([
            "topic": "realtime:public:messages",
            "event": "phx_join",
            "payload": [
                "config": ["postgres_changes": changes],
                // ⚠️ 这个字段很关键：服务器的权限规则（RLS）要靠它知道"你是谁"。
                //    不带它的话，按行过滤会失效或者什么都收不到。
                "access_token": accessToken ?? config.anonKey,
            ],
            "ref": "1",
        ], on: socket)
    }

    private func sendFrame(_ object: [String: Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await socket.send(.string(text))
    }

    // MARK: - 处理收到的帧

    private func handle(_ text: String, _ continuation: AsyncStream<MessageRow>.Continuation) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String
        else { return }

        switch event {

        case "postgres_changes":
            // 形状：{"event":"postgres_changes",
            //        "payload":{"data":{"type":"INSERT","record":{...}}}}
            guard let payload = object["payload"] as? [String: Any],
                  let body = payload["data"] as? [String: Any],
                  let record = body["record"] as? [String: Any]
            else { return }

            if let row = Self.decodeRow(record) {
                continuation.yield(row)
            }

        case "phx_reply":
            let status = (object["payload"] as? [String: Any])?["status"] as? String
            if status == "ok" {
                AppLog.info(.network, "实时频道已连上")
            } else {
                // 加入失败通常是权限规则拦住了 —— 这条日志能省很多排查时间
                AppLog.error(.network, "加入实时频道失败：\(text.prefix(300))")
            }

        case "phx_error":
            AppLog.error(.network, "实时频道出错：\(text.prefix(300))")

        default:
            break   // 心跳回复之类，不用管
        }
    }

    /// 把服务器推来的 record 变成 MessageRow。
    /// 走和 REST 完全相同的那套解码规则，避免两条路的字段解释不一致。
    private static func decodeRow(_ record: [String: Any]) -> MessageRow? {
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return nil }
        return try? SupabaseClient.jsonDecoder.decode(MessageRow.self, from: data)
    }
}
