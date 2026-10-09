import Foundation

/// App 自己的「网址方案」（`huami://`）。
///
/// 【它解决什么问题】
///
/// 用户在邮件里点「确认邮箱」之后，Supabase 验证完会把他跳转到一个网址。
/// 之前那个网址是 `https://huamidev.com` —— 于是浏览器打开了你的网站，
/// 而那个网站**不知道刚才发生了什么**，所以什么提示都没有：
///
///     点链接 → 跳到一个陌生网页 → 「验证成功了吗？不知道」
///
/// 现在改成跳回 `huami://confirm`：iOS 看到这个方案就会**打开我们的 App**，
/// App 里直接告诉他结果。**不用做网页，也不用他自己切回 App。**
enum AppLink {

    static let scheme = "huami"

    /// 确认邮箱成功后跳回来的地址。
    ///
    /// ⚠️ 这个字符串有**三处**必须一致，改一处就要改三处：
    ///   1. 这里
    ///   2. `Config/Info.plist` 里注册的方案（`huami`）
    ///   3. Supabase 后台 Redirect URLs 白名单里加的那条
    static let confirmURL = "huami://confirm"

    /// 加好友的码里装的东西。
    ///
    /// 【为什么不是一个纯用户名，而是一个链接】
    ///
    /// 原来二维码里装的就是"test002"这串字。用系统相机扫它，
    /// iOS 只会把它当普通文本显示出来 —— **不会打开 App，也加不了好友**。
    ///
    /// 换成 `huami://add?u=test002` 之后：
    ///   · 系统相机认得这是个链接，点一下就直接打开 App
    ///   · 打开之后落在"加好友"流程里，用户名已经填好
    ///   · 微信、备忘录这些能识别链接的地方也一样能用
    ///
    /// 顺带说一句：这也是为什么 `huami` 这个方案必须注册在 Info.plist 里
    /// （已经注册了）。
    static func addURL(username: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "add"
        components.queryItems = [URLQueryItem(name: "u", value: username)]
        return components.url ?? URL(string: "\(scheme)://add?u=\(username)")!
    }

    /// 从"加好友"的链接里取出用户名。
    /// 不是这类链接就返回 nil（调用方据此判断该走哪条路）。
    static func addUsername(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "add" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let raw = items?.first(where: { $0.name == "u" })?.value else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 从跳回来的链接里取出登录凭证。
    ///
    /// 【为什么凭证在 `#` 后面而不是 `?` 后面】
    ///
    /// Supabase 用的是 OAuth 的 "implicit flow" —— 凭证放在 URL 的
    /// **片段（fragment）**里。这样设计的目的是：
    /// **片段不会被浏览器发到服务器**，也就不会进服务器日志和中间代理，
    /// 减少凭证泄露的机会。
    ///
    /// 代价是 `URLComponents` 不会帮我们解析它，得自己按 `&` 和 `=` 拆。
    static func tokens(from url: URL) -> (access: String, refresh: String?)? {
        guard url.scheme == scheme else { return nil }

        // 片段优先；查询参数兜底（不同版本的 Supabase 行为略有差异）
        let raw = url.fragment ?? url.query ?? ""
        guard !raw.isEmpty else { return nil }

        var values: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            values[String(parts[0])] = value
        }

        guard let access = values["access_token"], !access.isEmpty else { return nil }
        return (access, values["refresh_token"])
    }
}
