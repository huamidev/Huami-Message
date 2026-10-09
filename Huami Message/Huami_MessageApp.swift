import SwiftUI
// 需要显式导入 SwiftData，因为下面用到了 database.mainContext。
// 工程开了「成员导入可见性」检查：用到哪个模块的成员就得导入哪个模块，
// 这样代码的依赖关系一目了然，不会靠"别人刚好导入了"侥幸编译通过。
import SwiftData

/// App 的入口。
///
/// 这里只做两件事：
///   1. 建一份本地数据库（整个 App 只有一份）
///   2. 把「数据管家」交给 RootView
///
/// 入口保持这么干净，是为了以后加东西时不至于在这里堆成一团。
@main
struct Huami_MessageApp: App {

    /// 本地数据库。
    /// 在这里建（而不是每个页面各建一份），是为了保证所有页面看到的是同一份数据。
    private let database: ModelContainer

    /// 数据管家。**只建一次。**
    ///
    /// ⚠️ 这里原来写的是 `RootView(store: ChatStore(...))` —— 直接在 body 里建。
    ///
    /// 那是个**真 bug**，不只是慢：body 会被 SwiftUI 重算多次
    /// （状态变化、尺寸变化、切前后台……），每重算一次就造一个新的 ChatStore，
    /// 于是**草稿、未读、内存里刚发出去还没落盘的消息全部丢掉**。
    /// 而且每造一次都要重新读一遍全部会话和消息。
    ///
    /// Store 是"整个 App 一份"的东西，它的生命周期就该和 App 一样长。
    private let store: ChatStore

    init() {
        // 让"启动后多久"从这一刻算起 —— 不然它会从第一条日志才算起。
        AppLog.markLaunch()

        let watch = Stopwatch()
        database = AppDatabase.make()
        AppLog.info(.data, "本地数据库就绪，耗时 \(Stopwatch.format(watch.milliseconds))")

        // mainContext 是"主线程上用的那个数据库连接"。
        // 界面相关的读写走它，是苹果推荐的默认做法。
        let storeWatch = Stopwatch()
        store = ChatStore(local: SwiftDataLocalStore(context: database.mainContext))
        AppLog.info(.data, "数据管家就绪，耗时 \(Stopwatch.format(storeWatch.milliseconds))")
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
