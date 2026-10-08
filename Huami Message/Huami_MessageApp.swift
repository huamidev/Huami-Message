import SwiftUI

/// App 的入口。
///
/// 这里只做一件事：把 RootView 显示出来。
/// 具体长什么样、有哪些页面，全在 RootView 里 ——
/// 入口文件保持这么干净，是为了以后加东西时不至于在这里堆成一团。
@main
struct Huami_MessageApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
