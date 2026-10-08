import SwiftUI

/// App 的三个一级页面。
///
/// 【为什么是这三个，而不是微信那四个】
///
/// 你原来的骨架是「微信 / 通讯录 / 发现 / 我」—— 那是一比一复刻微信。
/// 我们改成「消息 / 军师 / 我」，有两个原因：
///
/// 1. 避开商标和「像微信」这两件事。名字里带「微信」是直接侵权，
///    四个 Tab 复刻微信结构是最典型的「又一个微信」信号，审核会抓。
///
/// 2. 更重要的是产品本身：把「军师」放在一级 Tab，用户一打开就知道
///    这个 App 的重点不是聊天，是「帮你把话说好」。
///    产品定位应该能被第一眼看到，而不是藏在某个二级菜单里。
struct RootView: View {

    /// 数据管家由外部注入（在 Huami_MessageApp 里创建）。
    ///
    /// 为什么用"注入"而不是在这里自己 new 一个？
    /// 因为它依赖本地数据库，而"数据库怎么建"是 App 启动该管的事。
    /// 让每个页面自己造数据库，迟早会出现"两个页面看的数据不一样"的怪问题。
    let store: ChatStore

    enum Tab { case messages, advisor, profile }

    @State private var selection: Tab = RootView.initialTab

    /// 启动时默认停在哪个页面。
    /// 开发时可以用启动参数直接跳过去（见 Support/DevFlags.swift），
    /// 平时正常启动就是「消息」页，不受影响。
    static var initialTab: Tab {
        switch DevFlags.startTab {
        case "advisor": .advisor
        case "profile": .profile
        default:        .messages
        }
    }

    var body: some View {
        // 注意：这里**没有**放 AppBackground()。
        // 极光背景放在每个页面内部（见 Design/AppPage.swift 里的说明）——
        // 放在这里会被 TabView 自己的不透明背景盖住，变成一片死黑。
        TabView(selection: $selection) {
            ConversationListView()
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(Tab.messages)

            AdvisorView()
                .tabItem {
                    Label("军师", systemImage: "sparkles")
                }
                .tag(Tab.advisor)

            ProfileView()
                .tabItem {
                    Label("我", systemImage: "person.crop.circle.fill")
                }
                .tag(Tab.profile)
        }
        .tint(Theme.accent)
        // 把数据管家交给下面所有页面
        .environment(store)
        // 第一版只做深色。
        // 这是个刻意的取舍：极光背景 + 毛玻璃在深色下最好看，
        // 而且只做一套配色能省掉将近一半的界面工作量。
        // 以后要做浅色，改 Theme.swift 加一套配色就行，界面不用动。
        .preferredColorScheme(.light)
        .task { await store.start() }
    }
}
