import SwiftUI

/// 全局视觉基调（习惯上叫「设计系统」）。
///
/// 为什么要单独搞一个文件：整个 App 的颜色、圆角都从这里取。
/// 以后你想整体换风格（比如换主色、把圆角调小），只改这一个文件就行，
/// 不用去二十个界面里一处处找。这是「能长期维护」和「改一处崩三处」的分界线。
enum Theme {

    // MARK: - 品牌色

    /// 主色：青蓝。
    /// 刻意避开微信的绿 —— 一眼就让人知道这不是微信，审核时也少一个「像微信」的信号。
    static let accent = Color(red: 0.35, green: 0.63, blue: 1.00)

    /// 主色的搭档色（偏紫），用来给我发出的消息气泡做渐变
    static let accentDeep = Color(red: 0.55, green: 0.37, blue: 0.98)

    /// 一个提神的青绿，用在「更简短」和隐私提示上
    static let mint = Color(red: 0.20, green: 0.85, blue: 0.78)

    // MARK: - 圆角

    static let cardRadius: CGFloat = 22
    static let bubbleRadius: CGFloat = 20

    // MARK: - 我发出的消息气泡：主色渐变

    static var myBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
