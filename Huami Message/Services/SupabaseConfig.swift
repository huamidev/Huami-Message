import Foundation

// ============================================================================
// Supabase 连接信息
// ============================================================================
//
// 【这个文件解决的问题】
//
// 你注册完 Supabase 之后，只要把两个值填进一个文件，
// **App 就会自动从"演示模式"变成"真服务器模式"** —— 不用改任何代码。
//
// 【怎么填】
//
// 在 `Huami Message/` 目录下建一个叫 `Secrets.plist` 的文件：
//
//   <?xml version="1.0" encoding="UTF-8"?>
//   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
//     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
//   <plist version="1.0">
//   <dict>
//       <key>SUPABASE_URL</key>
//       <string>https://你的项目.supabase.co</string>
//       <key>SUPABASE_ANON_KEY</key>
//       <string>eyJhbGciOi...</string>
//   </dict>
//   </plist>
//
// ⚠️ 这个文件已经在 `.gitignore` 里，**不会被提交到代码仓库**。
//    这不是因为 anon key 是秘密（它本来就是公开的、要写进 App 里的），
//    而是因为"哪个项目对应哪份代码"这种信息没必要公开。
//
// ⚠️ **绝对不要把 service_role key 填到这里。**
//    那把钥匙能绕过所有权限规则读写整个数据库，放进 App 等于把门钥匙贴在门上。
//
// ============================================================================

struct SupabaseConfig {

    let url: URL
    let anonKey: String

    // MARK: - 从哪来

    /// 当前生效的配置。nil 表示没配置 —— 这时 App 用演示数据。
    ///
    /// 缓存成 static let：plist 不会变，没必要每次读盘。
    static let current: SupabaseConfig? = override ?? fromPlist

    /// 开发用：用启动参数覆盖。
    ///
    /// 为什么需要它：写客户端的时候不可能每次都去连真的 Supabase，
    /// 但"没连过真的"就没法验证代码是对的。
    /// 有了这个口子，我可以在本机起一个假的 Supabase 服务，
    /// 让 App 连上去跑完整流程（见 tools/fake-supabase/）。
    ///
    ///   -supabaseURL http://127.0.0.1:54321 -supabaseKey test
    private static let override: SupabaseConfig? = {
        let defaults = UserDefaults.standard
        guard let urlString = defaults.string(forKey: "supabaseURL"),
              let key = defaults.string(forKey: "supabaseKey"),
              !urlString.isEmpty, !key.isEmpty,
              let url = URL(string: urlString)
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }()

    /// 从 `Secrets.plist` 读
    private static let fromPlist: SupabaseConfig? = {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let raw = NSDictionary(contentsOfFile: path) as? [String: Any],
              let urlString = raw["SUPABASE_URL"] as? String,
              let key = raw["SUPABASE_ANON_KEY"] as? String
        else { return nil }

        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let anonKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        // 空值、或者还是模板里的占位文字，都当成"没配置"。
        // 这一条是为了防止"填了个假的进去，然后对着一堆网络错误发呆"。
        guard !url.isEmpty, !anonKey.isEmpty,
              !url.contains("你的项目"), !url.contains("YOUR_"),
              let parsed = URL(string: url), parsed.scheme != nil
        else { return nil }

        return SupabaseConfig(url: parsed, anonKey: anonKey)
    }()

    // MARK: - 一些拼 URL 的小工具

    /// `https://xxx.supabase.co/auth/v1/token`
    func endpoint(_ path: String) -> URL {
        // 注意用 appending(path:) 而不是 appendingPathComponent:
        // 前者会正确处理斜杠，也不会把路径里的字符做百分号转义
        url.appending(path: path)
    }

    /// 给日志用的安全描述 —— **绝不能把 anon key 打进日志**
    var debugDescription: String {
        "Supabase(\(url.host() ?? "?"), key: \(anonKey.prefix(6))…)"
    }
}
