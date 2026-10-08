import SwiftUI

/// App 的一级页面。
///
/// 【为什么是「消息 / 我」这两个，而不是微信那四个】
///
/// 你原来的骨架是「微信 / 通讯录 / 发现 / 我」—— 那是一比一复刻微信。
/// 名字里带「微信」是直接侵权，四个 Tab 复刻微信结构也是最典型的
/// 「又一个微信」信号，审核会抓。
///
/// 【为什么「军师」不再是底部 Tab】
///
/// 一开始我把它做成了一个独立 Tab，但那是错的：
/// 它的工作是「看懂对方说的话，帮你想怎么回」——
/// 那它就该待在**对话发生的那个界面里**。
/// 让用户把对方的话复制出来、切到另一个 Tab、再粘进去，是白白多出来的两步。
///
/// 现在它是聊天页里一个悬浮的小按钮（见 ChatView.assistantButton），
/// 点开就已经看得见你正在聊的那段对话。
struct RootView: View {

    /// 数据管家由外部注入（在 Huami_MessageApp 里创建）。
    ///
    /// 为什么用"注入"而不是在这里自己 new 一个？
    /// 因为它依赖本地数据库，而"数据库怎么建"是 App 启动该管的事。
    /// 让每个页面自己造数据库，迟早会出现"两个页面看的数据不一样"的怪问题。
    let store: ChatStore

    enum Tab { case messages, profile }

    @State private var selection: Tab = RootView.initialTab

    /// 是否已经同意过服务条款。
    /// 用 AppStorage 存 —— 只问一次，之后不再打扰。
    @AppStorage("hasAcceptedLegalTerms") private var hasAcceptedTerms = false

    /// 登录状态管家。
    /// 它不依赖数据库，所以在这里直接建就行。
    @State private var auth = AuthStore()

    /// 启动时默认停在哪个页面。
    /// 开发时可以用启动参数直接跳过去（见 Support/DevFlags.swift），
    /// 平时正常启动就是「消息」页，不受影响。
    static var initialTab: Tab {
        switch DevFlags.startTab {
        case "profile": .profile
        default:        .messages
        }
    }

    var body: some View {
        // 注意：这里**没有**放 AppBackground()。
        // 背景放在每个页面内部（见 Design/AppPage.swift 里的说明）——
        // 放在这里会被 TabView 自己的不透明背景盖住，一点都看不见。
        TabView(selection: $selection) {
            ConversationListView()
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(Tab.messages)

            ProfileView()
                .tabItem {
                    Label("我", systemImage: "person.crop.circle.fill")
                }
                .tag(Tab.profile)
        }
        .tint(Theme.accent)
        // 把数据管家交给下面所有页面
        .environment(store)
        .environment(auth)
        // 只做浅色一套配色。
        // 这是个刻意的取舍：一套配色能省掉将近一半的界面工作量，
        // 而且浅色更像 TIM 那种"办公软件"的感觉。
        // 以后要做深色，改 Theme.swift 加一套色值就行，界面不用动。
        .preferredColorScheme(.light)
        // 首次启动必须先同意条款。
        //
        // 这是 App Store 审核指南 1.2 条的硬性要求：
        // 能互发消息的 App，必须有写明零容忍条款的用户协议，且用户要明确同意。
        //
        // Binding 的 set 写成空操作，配合 interactiveDismissDisabled：
        // 这一页**只能通过点「同意并继续」离开**，往下划关不掉。
        // 一个能滑走的同意页，等于没有同意。
        .fullScreenCover(isPresented: Binding(
            get: { !hasAcceptedTerms || !auth.isSignedIn },
            set: { _ in }
        )) {
            // 两道闸门，顺序不能反：
            //   ① 先同意条款（审核要求，且要看懂我们在拿数据做什么）
            //   ② 再登录（不然没有身份，谁也加不了谁）
            Group {
                if !hasAcceptedTerms {
                    TermsGateView {
                        withAnimation(.snappy) { hasAcceptedTerms = true }
                    }
                } else {
                    AuthGateView()
                }
            }
            // ⚠️ 必须在这里**再注入一次**环境。
            //
            // 外面那句 .environment(auth) 挂在 TabView 上，而 .fullScreenCover
            // 是之后才挂上去的 —— 弹出来的内容**没有继承到**那个环境。
            // 结果 AuthGateView 里的 @Environment(AuthStore.self) 取不到值，
            // 直接触发断言崩溃（崩溃栈顶是 EnvironmentValues.subscript.getter）。
            //
            // 这个坑很典型：**弹窗 / 全屏覆盖的内容，环境要显式传**。
            .environment(store)
            .environment(auth)
            .interactiveDismissDisabled()
        }
        .task {
            // 开发用开关
            if DevFlags.resetTerms { hasAcceptedTerms = false }
            if DevFlags.acceptTerms { hasAcceptedTerms = true }

            // 开发用：自动建号并登录，省得每次截图都手打
            if DevFlags.devSignIn, auth.account == nil {
                await auth.signUp(email: DevFlags.devEmail,
                                  password: DevFlags.devPassword,
                                  confirmPassword: DevFlags.devPassword)
                if auth.account == nil {
                    // 已经注册过就直接登录
                    await auth.signIn(email: DevFlags.devEmail, password: DevFlags.devPassword)
                }
            }

            await store.start()
            // 开发自检：启动并加载完之后，执行一次"删除账号"，验证真的清干净
            if DevFlags.devWipe {
                try? await Task.sleep(for: .milliseconds(500))
                store.deleteEverything()
            }
        }
    }
}
