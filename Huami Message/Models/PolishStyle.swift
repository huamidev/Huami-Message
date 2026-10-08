import SwiftUI

/// 「多版本润色」的三种风格 —— 这是你在第一步拍板的产品决策。
///
/// 为什么偏偏是这三种，而不是「更正式 / 更随意」？
/// 因为用户打完一句话准备发出去时，心里真正纠结的其实是三件事：
///   · 会不会太冲？  → 得体
///   · 会不会太啰嗦？→ 简短
///   · 会不会太冷？  → 温度
/// 这三种正好覆盖日常社交里最常见的三种「说不出口」。
///
/// 想改风格？只改这个文件，界面会自动跟着变（因为界面是遍历 allCases 画的）。
enum PolishStyle: String, CaseIterable, Identifiable {
    case tactful   // 得体
    case concise   // 简短
    case warm      // 温度

    var id: String { rawValue }

    /// 卡片上显示的名字
    var title: String {
        switch self {
        case .tactful: "更得体"
        case .concise: "更简短"
        case .warm:    "更有温度"
        }
    }

    /// 一句话说明它到底改了什么，让用户不用猜
    var subtitle: String {
        switch self {
        case .tactful: "把话说圆，适合工作、长辈、不太熟的人"
        case .concise: "砍掉啰嗦，只说重点"
        case .warm:    "加一点关心，适合在乎的人"
        }
    }

    var icon: String {
        switch self {
        case .tactful: "hand.raised.fill"
        case .concise: "scissors"
        case .warm:    "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .tactful: Theme.accent
        case .concise: Theme.mint
        case .warm:    Color(red: 1.00, green: 0.45, blue: 0.55)
        }
    }
}
