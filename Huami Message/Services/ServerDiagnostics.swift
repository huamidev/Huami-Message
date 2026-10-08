import Foundation

// ============================================================================
// 服务器自检
// ============================================================================
//
// 【它解决什么问题】
//
// 接上真服务器之后，有几件事必须在 Supabase 后台手动做一遍：
//   · 建数据库的表（跑 schema.sql）
//   · 关掉「Confirm email」
//   · 部署 AI 云函数
//
// 漏掉任何一件，App 都会以一种**很难懂**的方式失败：
// 注册完登不进去、好友列表永远空的、AI 一直转圈……
// 报错信息通常是 "PGRST205" 或者干脆什么都不说。
//
// 这个项目里"开发者"和"用户"是同一个人，所以让 App **自己说清楚
// 哪里没配好、要去点哪里**，比任何文档都管用。
//
// 【为什么不担心它影响真实用户】
//
// 配置正确的服务器上，这些检查全都会通过，界面什么都不显示。
// 也就是说它是**自己会消失**的 —— 不需要有人记得上线前删掉。
//
// ============================================================================

/// 一条"服务器还没配好"的问题
struct ServerIssue: Identifiable, Hashable {

    let id: String

    /// 一句话说清是什么问题
    let title: String

    /// 为什么这事重要（不解释的话，用户凭什么照做）
    let detail: String

    /// 具体去点哪里。**必须是能照着做的步骤**，不能是"配置一下服务器"。
    let steps: [String]
}

enum ServerDiagnostics {

    /// 检查服务器。返回空数组表示一切正常。
    ///
    /// 只检查**确定是配置问题**的情况。网络不通之类的临时故障不在这里报 ——
    /// 那种情况下一刷新可能就好了，弹一堆提示只会让人以为坏了。
    static func check(_ client: SupabaseClient) async -> [ServerIssue] {
        var issues: [ServerIssue] = []

        // ── ① 数据库的表建了没有 ──
        do {
            let _: [ProfileRow] = try await client.get(
                "/rest/v1/profiles",
                query: [
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "limit", value: "1"),
                ],
                as: [ProfileRow].self
            )
        } catch SupabaseError.http(let status, let message)
                    where status == 404 || message.contains("PGRST205") {
            issues.append(ServerIssue(
                id: "schema",
                title: "数据库的表还没建",
                detail: "没有表就存不了账号资料、好友和消息。"
                      + "现在注册会成功，但登录之后什么都看不到。",
                steps: [
                    "打开 Supabase 控制台，左侧点 SQL Editor",
                    "点 New query",
                    "把项目里的 supabase/schema.sql 全部复制、粘贴进去",
                    "点 Run，看到 Success. No rows returned 就对了",
                ]
            ))
        } catch {
            // 其它错误（网络、超时）不在这里报
            AppLog.info(.network, "自检：读 profiles 时遇到其它错误，跳过（\(error)）")
        }

        // ── ② 邮箱验证开了没有 ──
        do {
            let settings: AuthSettings = try await client.get(
                "/auth/v1/settings",
                as: AuthSettings.self
            )
            if settings.mailerAutoconfirm == false {
                issues.append(ServerIssue(
                    id: "confirm-email",
                    title: "邮箱验证还开着",
                    detail: "开着的话，注册完必须去邮箱点确认链接才能登录。"
                          + "而 Supabase 免费版自带的邮件服务一小时只发得了几封 —— "
                          + "你朋友很可能根本收不到信，会以为 App 坏了。",
                    steps: [
                        "Supabase 控制台左侧点 Authentication",
                        "找到 Sign In / Providers（有的版本叫 Providers），点 Email",
                        "把 Confirm email 关掉",
                        "点 Save",
                    ]
                ))
            }
        } catch {
            AppLog.info(.network, "自检：读 auth 设置失败，跳过（\(error)）")
        }

        // ── ③ AI 云函数部署了没有 ──
        if !issues.isEmpty {
            // 前面已经有问题了，再列 AI 只会让人更乱。
            // 等前面修好了，下次启动再查这一条。
        } else {
            // 发一个**专门的探针**（mode=ping）问函数在不在。
            //
            // 【为什么不用 GET】
            // 两个原因：
            //   · 真实部署后函数未必响应 GET，会误报"还没部署"
            //   · 用别的 POST 探针可能真的触发一次 AI 调用 —— 那是要花钱的
            //
            // 云函数那边对 ping 是**直接返回、不调用 DeepSeek** 的。
            do {
                try await client.post("/functions/v1/ai-proxy", body: PingProbe())
            } catch SupabaseError.http(let status, _) where status == 404 {
                issues.append(ServerIssue(
                    id: "ai-function",
                    title: "AI 云函数还没部署",
                    detail: "没有它，AI 润色和小助手用不了（聊天不受影响）。"
                          + "另外提醒：AI 的密钥绝对不能放进 App，必须放在云函数里。",
                    steps: [
                        "在电脑上装 Supabase 命令行工具（supabase CLI）",
                        "在项目目录运行 supabase functions deploy ai-proxy",
                        "再运行 supabase secrets set DEEPSEEK_API_KEY=你的密钥",
                    ]
                ))
            } catch {
                // 函数存在（可能返回 405 之类），或者网络问题 —— 都按"没问题"处理
            }
        }

        return issues
    }
}

/// 探针的请求体。云函数见到 mode == "ping" 会直接回一句 pong，不调用 AI。
private struct PingProbe: Encodable {
    let mode = "ping"
}

/// `/auth/v1/settings` 里我们关心的字段
private struct AuthSettings: Decodable {
    let mailerAutoconfirm: Bool
}
