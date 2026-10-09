import Foundation
import UserNotifications
import UIKit

/// 本机提醒：新消息的通知，以及 App 图标上的红点。
///
/// 【为什么需要它 —— 我们没有推送】
///
/// 真正的推送要 99 美元的开发者账号。这一版用的是第三方个人证书，
/// 用不了推送，所以**别人给你发消息时，手机不会响**。
///
/// 这是当前最大的体验缺口：一个聊天软件不提醒，等于要用户自己去猜。
///
/// 在"没有推送"这个前提下，能做的是三件事，可靠程度依次下降：
///
///   ① **App 图标上的红点** —— 完全可靠，锁屏界面就看得见。
///      用户瞟一眼手机就知道"有消息"，这就解决了大半问题。
///   ② **不在那个聊天里时，本机弹一条通知** —— 可靠。
///      App 在前台时也能弹（需要下面那个 delegate）。
///   ③ **后台刷新** —— 尽力而为。系统按你的使用习惯决定给不给机会，
///      可能几小时才一次。所以它只能算"顺便多收一点"，
///      不能当成提醒手段。
///
/// 这三件事合起来，**不能替代推送**，但能让"完全不知道"变成"瞟一眼就知道"。
/// 等以后买了开发者账号，把真推送接上，这个文件里的通知发送逻辑可以直接复用。
@MainActor
final class MessageNotifier: NSObject {

    static let shared = MessageNotifier()

    /// 通知中心。单独存一份，省得每处都写一长串。
    private let center = UNUserNotificationCenter.current()

    /// 用户到底同不同意。不同意就什么都别做 ——
    /// 反复请求权限会被系统忽略，而且很烦。
    private(set) var isAuthorized = false

    private override init() { super.init() }

    /// App 启动时调一次。
    ///
    /// 顺便把 delegate 装上：**不装的话，App 在前台时通知不会显示**。
    /// 而这个 App 大多数时候就在前台（用户正看着），所以这一条很关键。
    func start() {
        center.delegate = self

        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                // 只在第一次问。弹窗要说明"为什么要打扰你" ——
                // 什么都不说就要权限，用户会点拒绝。
                isAuthorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )) ?? false
            default:
                isAuthorized = false
            }
            AppLog.info(.data, "本机提醒：\(isAuthorized ? "已允许" : "没允许（图标红点和通知都不会有）")")
        }
    }

    /// 收到别人的新消息时调。
    ///
    /// - Parameters:
    ///   - name: 谁发的（群聊里传群名）
    ///   - body: 消息内容（语音、图片这类会变成「[语音]」）
    ///   - conversationID: 这条消息属于哪段会话 —— 用户正在看这段会话时不用打扰他
    func notifyNewMessage(from name: String, body: String, conversationID: UUID) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = name
        content.body = body.isEmpty ? "发来一条消息" : body
        content.sound = .default
        // 带上会话 id：以后点通知能直接跳到那个聊天
        content.userInfo = ["conversationID": conversationID.uuidString]

        // 一秒后触发。用触发器而不是立刻投递，是因为立刻投递的通知
        // 在 App 前台时有时会被合并掉；给一秒缓冲更稳。
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    /// 更新 App 图标上的数字。
    ///
    /// 这是三件事里**最可靠**的一件 —— 不依赖 App 在不在跑，
    /// 系统自己就会把它画在图标上。
    func updateBadge(unreadTotal: Int) {
        guard isAuthorized else { return }
        // 负数会被系统拒绝，钳一下
        center.setBadgeCount(max(0, unreadTotal))
    }
}

extension MessageNotifier: UNUserNotificationCenterDelegate {

    /// App 在前台时也把通知显示出来。
    ///
    /// 默认行为是"前台不显示" —— 那对我们最没用，因为用户多数时候
    /// 就在前台（在看别的聊天）。所以明确要求显示。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
