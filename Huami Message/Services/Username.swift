import Foundation

/// 用户名的规矩。
///
/// 【为什么单独一个文件】
///
/// 因为**同一套规则要出现在两个地方**：
///   · 客户端 —— 边打字边拦，让用户当场知道行不行
///   · 数据库 —— 真正的防线（客户端可以被绕过）
///
/// 两边的规则必须一致。写成一处、引用着用，
/// 改的时候才不会出现"App 说可以、服务器说不行"这种最让人火大的情况。
///
/// 规矩（和数据库里的约束一一对应）：
///   · 5 到 20 位
///   · 字母开头
///   · 只有小写字母和数字
///   · 全小写（不区分大小写 = 一律存小写）
enum Username {

    static let minLength = 5
    static let maxLength = 20

    /// 把用户输入收拾成"该有的样子"。
    ///
    /// 一边打字一边过滤掉不合法的字符，比"输完了再报错"友好得多 ——
    /// 用户在输入的过程中就明白了规矩，而不是被打回来重填。
    ///
    /// 顺手全转小写：不区分大小写意味着 "Huami" 和 "huami" 是同一个名字，
    /// 那就在入口处统一成一种写法，别让它流到下游。
    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        // 只留 ASCII 字母和数字。
        //
        // 注意**不能用 `$0.isLetter`** —— 那会把中文、日文、重音字母
        // 都算成字母，于是 "张三" 也能通过，和数据库的正则对不上。
        let filtered = lowered.filter { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
        return String(filtered.prefix(maxLength))
    }

    /// 检查。没问题返回 nil，有问题返回**能照做的一句话**。
    static func problem(with value: String) -> String? {
        if value.isEmpty { return "取一个名字吧" }
        if value.count < minLength { return "至少要 \(minLength) 位" }
        if value.count > maxLength { return "最多 \(maxLength) 位" }
        guard let first = value.first else { return "取一个名字吧" }
        if !(first.isASCII && first.isLetter) {
            return "要用字母开头（不能是数字）"
        }
        // normalize 已经过滤过字符，这里再确认一次，
        // 防止有人把没过滤的值直接传进来
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "只能用英文字母和数字"
        }
        return nil
    }

    static func isValid(_ value: String) -> Bool {
        problem(with: value) == nil
    }
}
