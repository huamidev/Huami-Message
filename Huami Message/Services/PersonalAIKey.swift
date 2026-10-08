import Foundation

/// 用户自己填的 AI 密钥（可选）。
///
/// 【为什么要有这个东西】
///
/// 默认用的是搭这个 App 的人配在服务器上的密钥 —— 也就是说，
/// **所有朋友的 AI 花费都压在一个人头上**。人一多就撑不住。
///
/// 所以留一个口子：谁想用自己的 DeepSeek 账号，就填自己的密钥，
/// 花自己的钱。不想折腾的人什么都不用做，照常能用。
///
/// 【为什么存钥匙串而不是 UserDefaults】
///
/// 这是一串能直接花钱的凭证。UserDefaults 会被写进 iTunes 备份、
/// 也能被同一台设备上别的进程读到 —— 那不合适。
/// 钥匙串是系统给的、专门存这类东西的地方。
enum PersonalAIKey {

    private static let storageKey = "personal.deepseek.key"

    /// 当前填着的密钥（没填就是 nil）
    static var value: String? {
        guard let data = Keychain.load(storageKey),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var isSet: Bool { value != nil }

    /// 填进去的密钥长什么样才算数。
    ///
    /// 只做最基本的形状检查（`sk-` 开头、够长），**不去联网验证** ——
    /// 验证要花用户的钱，而且他大概率是刚复制过来还没充值。
    /// 真正不对的话，第一次用的时候会报错，那时候提示更准确。
    static func looksValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-") && trimmed.count >= 20
    }

    @discardableResult
    static func save(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        return Keychain.save(Data(trimmed.utf8), for: storageKey)
    }

    @discardableResult
    static func clear() -> Bool {
        Keychain.delete(storageKey)
    }

    /// 显示用的打码形式：`sk-abc…wxyz`
    /// 让用户确认"填的是哪一串"，又不至于被旁边的人看走。
    static var masked: String? {
        guard let key = value else { return nil }
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(7))…\(key.suffix(4))"
    }
}
