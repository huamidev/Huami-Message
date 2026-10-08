import SwiftUI

/// 聊天页里「一条一条」的东西。
///
/// 为什么需要这一层：聊天记录不是只有消息，中间还要插**日期分隔条**
/// （「今天」「昨天」「10月7日」）。直接把 [Message] 铺到界面上是插不进去的，
/// 所以先把它加工成「消息 + 分隔条」的混合列表。
///
/// 这样做的好处是：界面只需要遍历一个数组，不用在 view 里写判断逻辑。
enum ChatItem: Identifiable {

    case daySeparator(date: Date)
    case message(Message)

    var id: String {
        switch self {
        case .daySeparator(let date):
            // 用当天的零点当 id，同一天的分隔条永远只有一个身份
            "day-\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)"
        case .message(let message):
            message.id.uuidString
        }
    }

    /// 把消息列表加工成「带日期分隔条」的列表。
    ///
    /// 规则很简单：**日期一变，就插一条分隔条。**
    static func build(from messages: [Message]) -> [ChatItem] {
        var items: [ChatItem] = []
        var lastDay: Date?

        for message in messages {
            let day = Calendar.current.startOfDay(for: message.sentAt)
            if day != lastDay {
                items.append(.daySeparator(date: message.sentAt))
                lastDay = day
            }
            items.append(.message(message))
        }
        return items
    }
}

/// 日期分隔条的样子：一条半透明的毛玻璃小胶囊，居中小字。
///
/// 做得**克制**是有意的：它的作用是让人扫一眼就知道"这是另一天了"，
/// 不该抢消息的注意力。所以用小字 + 低对比度 + 毛玻璃，而不是加粗大字。
struct DaySeparatorView: View {

    let date: Date

    var body: some View {
        Text(Self.label(for: date))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.separator, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5) }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    /// 「今天 / 昨天 / 10月7日 / 2025年10月7日」
    ///
    /// 用相对说法（今天、昨天）而不是直接报日期，是因为人脑对
    /// "昨天"的感知比"10月7日"快得多 —— 这是个体验细节，但很值。
    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        // 同一年就不显示年份，少一点噪音
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        formatter.dateFormat = sameYear ? "M月d日 EEEE" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}
