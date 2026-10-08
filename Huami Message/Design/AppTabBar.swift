import SwiftUI

/// 四个页签。
///
/// 【为什么挪到了顶层】
///
/// 它原来声明在 `RootView` 里面。自己画底栏之后，`AppTabBar` 也要用它 ——
/// 而类型嵌在别的类型里，外面就看不见了（报错是
/// "cannot find type 'AppTab' in scope"）。
///
/// 一个类型被两个以上地方用，就该放在顶层。
enum AppTab: Hashable, CaseIterable {
    case messages, search, contacts, profile
}

/// 自己画的底栏。
///
/// 【为什么不用系统的】
///
/// 系统的悬浮底栏（iOS 26 起）**只让我决定"有哪些页签"** ——
/// 圆角、间距、大小、出现/消失的动画全归系统。
///
/// 实测撞到两个问题：
///   1. **同一个 `role: .search`，iOS 26.5 上是独立的圆钮，
///      iOS 27 上被合并进胶囊里。** 我这边模拟器看着对，用户手机上不对。
///   2. 进/出聊天页时底栏是**"啪"地突现**的，没有过渡。
///
/// 自己画之后：外观和动画都归我们，**而且任何 iOS 版本上长得都一样。**
/// 代价是安全区、无障碍标签这些要自己处理 —— 所以下面都写了。
struct AppTabBar: View {

    @Binding var selection: AppTab
    var onSearch: () -> Void

    /// 当前是不是停在搜索页（圆钮高亮）
    var searchActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // ── 三个主页签：一个胶囊 ──
            HStack(spacing: 0) {
                item(.messages, "消息", "bubble.left.and.bubble.right.fill")
                item(.contacts, "联系人", "person.2.fill")
                item(.profile, "我", "person.crop.circle.fill")
            }
            .padding(6)
            .background(bar)
            .clipShape(Capsule())

            // ── 搜索：独立的一个圆钮 ──
            //
            // **中间那 12 磅间距是我们自己定的** ——
            // 系统的做法里这个数改不了，而 Telegram 看着舒服，
            // 很大程度就是因为它留够了这个空隙。
            Button {
                Haptics.tap()
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(searchActive ? Theme.accent : Theme.textSecondary)
                    .frame(width: 54, height: 54)
                    .background(bar)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    // MARK: - 零件

    private var bar: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(Theme.surface.opacity(0.55))
        }
        .overlay {
            Capsule().strokeBorder(Theme.separator, lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
    }

    private func item(_ tab: AppTab, _ title: String, _ icon: String) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.22)) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(selection == tab ? Theme.accent : Theme.textSecondary)
            .frame(width: 76)
            .padding(.vertical, 8)
            .background {
                if selection == tab {
                    Capsule().fill(Theme.accentSoft)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 控制"系统外壳"状态的小盒子。
///
/// 现在只有一件事：**聊天页要把底栏藏起来**。
///
/// 为什么用一个共享对象而不是给 ChatView 传参：
/// 聊天页是从好几个地方压栈进去的（消息、联系人、搜索），
/// 每条路径都传一遍参数，迟早漏一个 —— 漏了的表现就是
/// "从搜索进去的聊天页底下还挂着底栏"。
@Observable
final class ChromeState {
    var hidesTabBar = false
}
