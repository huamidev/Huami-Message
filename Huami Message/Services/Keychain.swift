import Foundation
import Security

/// 把登录凭证存进系统的「钥匙串」。
///
/// 【为什么不能用 UserDefaults】
///
/// UserDefaults 存在 App 容器里的一个 plist 文件里，而那个文件会
/// **跟着 iTunes / iCloud 备份一起走**。备份要是不加密，
/// 换台电脑就能看到里面的字符串。
///
/// 登录凭证泄露 = 别人可以冒充你、读你所有的消息。这是这个 App 里
/// 最不能丢的东西，所以必须放对地方。
///
/// 钥匙串是系统专门为"秘密"准备的：加密存储、可以设置"只在设备解锁时可用"、
/// 不会进普通备份。
///
/// 代价是它的 API 是 CoreFoundation 风格的（`SecItemAdd` 那一套），
/// 又长又难读。所以下面包了一层，业务代码只需要 save / load / delete。
///
/// 【一个容易踩的点】
/// 钥匙串是按 App 的签名身份隔离的。开发时用的免费证书和上架后的正式证书
/// 算不同身份 —— 换证书后旧数据读不到是正常的，不是 bug。
enum Keychain {

    private static let service = Bundle.main.bundleIdentifier ?? "com.huamidev.HuamiMessage"

    /// 存（已存在就覆盖）
    @discardableResult
    static func save(_ data: Data, for key: String) -> Bool {
        // 先删再存。
        // 钥匙串的"更新"要单独走 SecItemUpdate，而"删掉重加"更短、更不容易出错。
        // 这点性能开销（微秒级）完全不值得用更复杂的代码去省。
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // 只在设备解锁时可读。
            // 我们不需要后台（锁屏时）访问钥匙串，那就别给这个权限。
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.error(.network, "钥匙串写入失败：\(status)")
        }
        return status == errSecSuccess
    }

    static func load(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // errSecItemNotFound 是正常的（第一次运行还没存过），不算错误
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
