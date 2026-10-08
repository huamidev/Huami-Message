import Foundation
import OSLog

/// 统一的日志出口。
///
/// 【为什么不用 print】
///
/// 我在前面几轮排查问题时吃过这个亏：**`print` 的输出在模拟器里抓不到**
/// （沙盒不允许开 pty），只能临时往文件里写，排查完还得记得删掉。
///
/// 换用 `os.Logger` 之后：
///   · 输出进系统统一日志，`xcrun simctl spawn booted log show` 就能读
///   · 真机上也能在「控制台」App 里看
///   · 自带分类，要只看"数据层"或只看"网络层"很方便
///   · 上架后用户导出日志，能帮你定位他遇到的问题
///
/// 【为什么外面看到的是一层普通函数，而不是 Logger 本身】
///
/// 因为工程开了「成员导入可见性」检查：**用到哪个模块的成员就得导入哪个模块**。
/// 如果直接把 `Logger` 暴露出去，那么每一个写日志的文件都得加 `import OSLog`,
/// 少一个就编译不过，而且报错信息不太好懂。
///
/// 把 Logger 关在这里面之后，调用方只需要：
///     AppLog.info(.data, "加载了 \(count) 个会话")
/// 不用关心底下用的是 os.Logger 还是别的什么 —— 以后想换成写文件也不用改调用方。
///
/// 顺带说一句：这个检查已经抓到我两次漏 import 了（一次 SwiftData、
/// 一次 os）。它有点烦，但确实在逼我把依赖关系写清楚。
enum AppLog {

    /// 日志的分类。以后要按模块过滤时用得着。
    enum Module: String {
        case data       // 数据层：本地数据库的读写、同步、合并
        case network    // 网络层：以后接 Supabase 用
        case ai         // AI：润色和小助手
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.huamidev.HuamiMessage"

    private static func logger(_ module: Module) -> Logger {
        Logger(subsystem: subsystem, category: module.rawValue)
    }

    /// 正常信息（「加载了 12 个会话，耗时 8ms」这种）
    static func info(_ module: Module, _ message: String) {
        logger(module).info("\(message)")
    }

    /// 出问题了。**只记录，不抛出去** ——
    /// 存不进数据库不该让 App 崩掉，用户还能继续用，只是这次没存下来。
    static func error(_ module: Module, _ message: String) {
        logger(module).error("\(message)")
    }
}

/// 计时小工具。
///
/// 为什么不用 `Date()`：系统时间会被用户改、会被时区影响，
/// 测"这段代码跑了多久"应该用**单调时钟**（只往前走、不受调时间影响）。
struct Stopwatch {

    private let start = ContinuousClock.now

    /// 从创建到现在经过了多少毫秒
    var milliseconds: Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000
             + Double(d.components.attoseconds) / 1_000_000_000_000_000
    }

    /// 跑一段代码并返回它花了多少毫秒
    static func measure(_ body: () -> Void) -> Double {
        let watch = Stopwatch()
        body()
        return watch.milliseconds
    }

    /// 把毫秒格式化成好读的样子（日志里用）
    static func format(_ ms: Double) -> String {
        ms < 1 ? String(format: "%.2fms", ms) : String(format: "%.1fms", ms)
    }
}
