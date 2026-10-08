import SwiftUI

/// 全局视觉基调（设计系统）。
///
/// 【风格定调：清爽的浅色，像 TIM 那样】
///
/// 之前是「深色 + 极光 + 毛玻璃」。现在换成浅色的、干净的、
/// 以内容为主的界面 —— 也就是 TIM 那种感觉：
///
///   · **浅灰底 + 白色卡片**：层次靠"白和灰的对比"做出来，不靠发光和模糊
///   · **一个明快的蓝**：只用在"需要被看见"的地方（按钮、未读红点、自己的气泡）
///   · **极细极淡的分隔线**：几乎看不见，但确实在，让信息有边界
///   · **文字分三级**：主 / 次 / 弱。这个比换字体对可读性的影响大得多
///
/// 换风格只改这一个文件 —— 这就是当初把它单独拎出来的目的。
/// 深色版的那套代码还在 git 历史里，想找回来随时可以。
enum Theme {

    // MARK: - 主色

    /// TIM 那种明快蓝。
    /// 用得越省，越有分量 —— 满屏都是蓝就变成廉价了。
    static let accent = Color(hex: 0x12B7F5)

    /// 主色的浅色调，用在做底色的地方（选中项、标签底）
    static let accentSoft = Color(hex: 0xE6F5FD)

    /// 我自己发出的消息气泡。
    /// 比主色压深一点，白字压得住，长时间看也不刺眼。
    static let myBubble = Color(hex: 0x12A9E8)

    /// 一点点青绿，用在"隐私""安全"这类需要安心的提示上
    static let mint = Color(hex: 0x00BFA5)

    /// 警告 / 提醒（"演示模式"这类标签）
    static let warning = Color(hex: 0xF5A623)

    /// 危险 / 出错（重试、删除）
    static let danger = Color(hex: 0xF5453D)

    // MARK: - 背景与面
    //
    // 这三个是浅色界面的骨架。分清它们，"干净"就有了：
    // 页面底是灰的、卡片是白的、输入框是更浅的灰。

    /// 页面底色：很浅的灰。纯白会让白色卡片陷进去，看不出层次
    static let background = Color(hex: 0xF2F3F5)

    /// 卡片 / 列表项：白
    static let surface = Color.white

    /// 次级面：输入框、代码块这类"陷下去"的地方
    static let surfaceAlt = Color(hex: 0xF7F8FA)

    /// 分隔线。浅到几乎看不见，但少了它界面会"糊"成一片
    static let separator = Color(hex: 0xE8E9EB)

    // MARK: - 文字（三级）

    /// 一级：标题、消息正文
    static let textPrimary = Color(hex: 0x1A1A1A)

    /// 二级：说明、摘要、次要信息
    static let textSecondary = Color(hex: 0x5A5F66)

    /// 三级：时间戳、占位提示这些"可以忽略但不能没有"的字
    static let textTertiary = Color(hex: 0x9AA0A6)

    // MARK: - 圆角

    static let cardRadius: CGFloat = 12
    static let bubbleRadius: CGFloat = 18

    // MARK: - 我发出的消息气泡

    /// 名字还叫 gradient，但其实是两档非常接近的蓝 ——
    /// 只是在边缘留一点点光泽，不是那种张扬的渐变。
    /// （改名字要动好几处调用点，而它确实还是"渐变"，就先留着。）
    static var myBubbleGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x18AEEA), Color(hex: 0x0FA0DE)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - 便利工具

extension Color {
    /// 用 0xRRGGBB 这种写法定义颜色。
    ///
    /// 比 `Color(red: 0.35, green: 0.63, blue: 1.00)` 好在两点：
    ///   · 跟设计稿 / 取色器上的数字一一对应，不用心算除以 255
    ///   · 改颜色的时候不容易抄错
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
