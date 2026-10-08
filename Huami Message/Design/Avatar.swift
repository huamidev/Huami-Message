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

    /// 头像照片的网址。没设置过就是 nil —— **那时仍然显示彩色渐变 + 首字**。
    ///
    /// 【为什么一定要保留"没有照片"这条路】
    ///
    /// 上传头像是"加餐"，不是必经之路。如果没上传就显示一块灰或者破图，
    /// 那些不想折腾的人（大多数）第一眼看到的就是坏掉的样子。
    ///
    /// 给默认值 nil 的好处：**所有老的调用点一行都不用改**，
    /// 谁有照片谁自己传。
    var url: URL? = nil

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
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        // scaledToFill + 固定尺寸：头像本来就是方的，
                        // 这样不会因为照片比例不同把列表撑歪
                        image.resizable().scaledToFill()
                    default:
                        // 加载中和失败**都退回彩色方块** ——
                        // 绝不留一块空白，列表里那样看起来就是坏了
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }

    /// 没有照片（或者照片还没加载出来）时的样子：彩色渐变 + 名字首字。
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}
