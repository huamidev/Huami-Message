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
    private let database = AppDatabase.make()

    var body: some Scene {
        WindowGroup {
            RootView(
                store: ChatStore(
                    // mainContext 是"主线程上用的那个数据库连接"。
                    // 界面相关的读写走它，是苹果推荐的默认做法。
                    local: SwiftDataLocalStore(context: database.mainContext)
                )
            )
        }
    }
}
