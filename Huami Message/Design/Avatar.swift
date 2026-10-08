import SwiftUI

/// 头像。
///
/// 现在还没有真头像，用一个「名字首字 + 渐变圆底」代替。
/// 颜色由 seed（一个数字）决定 —— 同一个好友每次进来颜色都一样，不会闪来闪去。
///
/// 为什么要存数字而不是直接存颜色：以后好友信息要从服务器来，
/// 颜色（Color）是没法存进数据库的，但一个数字可以。
struct Avatar: View {

    let initial: String
    let seed: Int
    var size: CGFloat = 52

    /// 四套配色，由 seed 稳定地挑一套
    private var colors: [Color] {
        let palettes: [[Color]] = [
            [Theme.accent, Theme.accentDeep],
            [Theme.mint, Color(red: 0.15, green: 0.55, blue: 0.95)],
            [Color(red: 1.00, green: 0.45, blue: 0.55), Color(red: 0.85, green: 0.30, blue: 0.75)],
            [Color(red: 1.00, green: 0.72, blue: 0.30), Color(red: 1.00, green: 0.42, blue: 0.35)],
        ]
        return palettes[abs(seed) % palettes.count]
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                // 和毛玻璃卡片同一道高光边，风格才统一
                Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
    }
}
