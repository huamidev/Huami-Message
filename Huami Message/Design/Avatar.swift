import SwiftUI

/// 头像。
///
/// TIM / QQ 的头像是**圆角方形**，不是圆形 —— 这个细节一眼就能看出"像不像"。
/// 所以这里用 RoundedRectangle 而不是 Circle。
///
/// 颜色由 seed（一个数字）决定，同一个好友每次进来颜色都一样，不会闪来闪去。
/// 存数字而不是存颜色，是因为好友信息以后要从服务器来，颜色存不进数据库。
struct Avatar: View {

    let initial: String
    let seed: Int
    var size: CGFloat = 48

    /// 六套配色。选了饱和度偏低、明度偏高的一组 ——
    /// 浅色界面里，头像太艳会抢走正文的注意力。
    ///
    /// 提成 static 是为了让"换底色"的选择器也能用同一份色表 ——
    /// 各写一份的话，改了这里忘了那里，头像和选色点就对不上了。
    static let palettes: [[Color]] = [
        [Color(hex: 0x4FA8F5), Color(hex: 0x2E8BE0)],
        [Color(hex: 0x3FC7B4), Color(hex: 0x22A695)],
        [Color(hex: 0xF57C8A), Color(hex: 0xE05A6B)],
        [Color(hex: 0xF5A94F), Color(hex: 0xE08E2E)],
        [Color(hex: 0x9B8CF5), Color(hex: 0x7A68E0)],
        [Color(hex: 0x6BBF6B), Color(hex: 0x4CA04C)],
    ]

    /// 第 seed 套配色（超出范围会绕回来）
    static func palette(_ seed: Int) -> [Color] {
        palettes[abs(seed) % palettes.count]
    }

    private var colors: [Color] { Self.palette(seed) }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
