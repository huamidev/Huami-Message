import Foundation
import SwiftData

/// 本地数据库的创建。
///
/// 把"怎么建数据库"单独放在一个文件里，是为了让 App 入口保持干净 ——
/// 入口只负责"用数据库"，不负责"怎么建数据库"。
enum AppDatabase {

    /// 建一个能落盘的本地数据库。
    ///
    /// 万一建不起来（磁盘满、结构变了……），**退化成内存模式**而不是崩溃。
    /// 这是个重要的取舍：崩溃对用户来说是最糟的结果 ——
    /// 退化成内存模式至少 App 还能打开、还能用，只是这次的东西存不下来。
    /// 对你自己调试也更友好，不会一改数据结构就开不了 App。
    static func make() -> ModelContainer {
        do {
            return try ModelContainer(
                for: StoredFriend.self,
                StoredMessage.self,
                StoredReport.self,
                StoredTombstone.self
            )
        } catch {
            print("⚠️ 本地数据库创建失败，退化成内存模式（数据重启后会丢）：", error)
            do {
                return try ModelContainer(
                    for: StoredFriend.self,
                    StoredMessage.self,
                    StoredReport.self,
                    StoredTombstone.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                // 连内存数据库都建不起来，说明是代码层面的严重错误，
                // 这时候直接崩掉、让问题暴露出来，比带着坏状态继续跑要好。
                fatalError("连内存数据库都建不起来，模型定义有问题：\(error)")
            }
        }
    }
}
