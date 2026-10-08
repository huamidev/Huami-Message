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

    /// 四个页签。
    ///
    /// 顺序：消息 / 联系人 / 我 / 搜索。
    /// 搜索**固定在最右边** —— 用户会闭着眼睛去点，位置定了就别动。
    ///
    /// 【为什么把"搜索"单独拎出来】
    ///
    /// 放在消息页顶上时，搜索框会**一直占着一条**，而它大部分时候是空着的。
    /// 独立成一页之后，进来就是全屏的结果列表，不用在列表和结果之间来回切。
    ///
    /// 【为什么有"联系人"而不是把加好友留在消息页】
    ///
    /// 加好友是"维护关系"的动作，不是"看消息"的动作。
    /// 消息页应该只有"最近聊过的人"。
    enum Tab { case messages, search, contacts, profile }

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
        case "profile":  .profile
        case "search":   .search
        case "contacts": .contacts
        default:         .messages
        }
    }

    var body: some View {
        // ⚠️ **必须在 body 里真的读一次**这个条件。
        //
        // 我原来只在下面 Binding 的 get 闭包里读它，结果是：
        // **点了「退出登录」，登录页不出现 —— 看起来像没反应。**
        //
        // 原因：SwiftUI 的依赖观察是靠"body 求值时读了哪些值"来建立的。
        // 只在 get 闭包里读，这个依赖不一定建立得起来，
        // 于是 isSignedIn 变了、body 却不重新求值，绑定也就不会更新。
        //
        // 在 body 里读一次之后，值一变整个 body 重新求值，绑定跟着更新。
        let needsGate = !hasAcceptedTerms || !auth.isSignedIn

        // 注意：这里**没有**放 AppBackground()。
        // 背景放在每个页面内部（见 Design/AppPage.swift 里的说明）——
        // 放在这里会被 TabView 自己的不透明背景盖住，一点都看不见。
        TabView(selection: $selection) {
            ConversationListView()
                .tabItem {
                    Label("消息", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(Tab.messages)

            ContactsView()
                .tabItem {
                    Label("联系人", systemImage: "person.2.fill")
                }
                .tag(Tab.contacts)

            ProfileView()
                .tabItem {
                    Label("我", systemImage: "person.crop.circle.fill")
                }
                .tag(Tab.profile)

            // ⚠️ 搜索放**最右边**（用户要求：和 Telegram 一样，
            // 搜索单独拎出来、位置固定在右手边）。
            // 这类"肌肉记忆"的位置一旦定了就别再动 ——
            // 用户会闭着眼睛去点，位置变了就会误触。
            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)
        }
        .tint(Theme.accent)
        // 把数据管家交给下面所有页面
        .environment(store)
        .environment(auth)
        // 只做浅色一套配色。
        // 这是个刻意的取舍：一套配色能省掉将近一半的界面工作量，
        // 而且浅色更像 TIM 那种"办公软件"的感觉。
        // 以后要做深色，改 Theme.swift 加一套色值就行，界面不用动。
        // 用户点邮件里的确认链接 → iOS 打开 App → 这里接住。
        //
        // 注意：**这个修饰符必须挂在最外层**，而不是某个子页面里。
        // 因为链接打开 App 的那一刻，用户可能停在任何界面
        //（多数时候是登录页，但也可能是已经登录后的某个页面）。
        .onOpenURL { url in
            Task { await auth.handleLink(url) }
        }
        // 用 overlay 画一条提示，**不用 .alert**。
        //
        // 【为什么】
        // 这个视图上已经挂了一个 .fullScreenCover（登录/条款的闸门）。
        // SwiftUI 里**同一个视图上挂多个"呈现型"修饰符会互相干扰** ——
        // 我第一版用 .alert，日志证明代码跑了（handleLink 有输出）、
        // 但提示根本没显示出来。
        //
        // overlay 不参与呈现机制，只是"画在上面"，没有这个问题。
        .overlay(alignment: .top) {
            if let message = auth.linkMessage {
                linkBanner(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: auth.linkMessage)
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
            // 用上面在 body 里读到的那个值，而不是在这里重新算一遍
            get: { needsGate },
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
            // ⚠️ 提示条**必须在这里也画一遍**。
            //
            // 因为 fullScreenCover 是**另一个层级** —— 主界面上画的任何东西
            // 都出现在它下面，被完全盖住。
            //
            // 而用户点完邮件里的确认链接之后，**绝大多数情况正是停在这一页**
            //（他刚注册完，还没登录）。只画在主界面上等于没画。
            //
            // 这就是我第一版"日志说跑了、界面却什么都没有"的真正原因 ——
            // 不是代码没执行，是**画错了层**。
            .overlay(alignment: .top) {
                if let message = auth.linkMessage {
                    linkBanner(message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.3), value: auth.linkMessage)
            .interactiveDismissDisabled()
        }
        // 开发用：自动建号并登录，省得每次截图都手打。
        //
        // ⚠️ **必须放在独立的 .task 里，不能放进下面那个同步任务。**
        //
        // 因为登录会让 auth.isSignedIn 变化，而下面那个任务的 id 就是它 ——
        // id 一变，SwiftUI 会**取消正在跑的旧任务**，正在飞的网络请求跟着一起断。
        // 我一开始就把它写在里面，结果同步在查档案那一步被取消了，
        // 日志显示"网络失败：cancelled"，看着像服务器的问题，其实是自己取消的。
        .task {
            guard DevFlags.devSignIn, auth.account == nil else { return }
            await auth.signUp(email: DevFlags.devEmail,
                              password: DevFlags.devPassword,
                              confirmPassword: DevFlags.devPassword)
            if auth.account == nil {
                // 已经注册过就直接登录
                await auth.signIn(email: DevFlags.devEmail, password: DevFlags.devPassword)
            }
        }
        // ⚠️ 用 `.task(id: auth.isSignedIn)` 而不是 `.task {`。
        //
        // 因为接上真服务器之后，**同步必须等登录完成**才开始 ——
        // 服务器要靠登录凭证才知道"该给你看哪些数据"。
        // 用 .task { } 的话它只跑一次，用户登录完就再也不会同步了。
        //
        // 加上 id 之后，登录状态一变这个任务就会重跑。
        .task(id: auth.isSignedIn) {
            // 开发用开关
            if DevFlags.resetTerms { hasAcceptedTerms = false }
            if DevFlags.acceptTerms { hasAcceptedTerms = true }

            // 开发自检：模拟"点了邮件里的确认链接"
            AppLog.info(.network, "dev 开关 confirmLink = [\(DevFlags.confirmLink)]")
            if !DevFlags.confirmLink.isEmpty, let url = URL(string: DevFlags.confirmLink) {
                try? await Task.sleep(for: .seconds(2))
                await auth.handleLink(url)
            }

            // 没登录就不同步 —— 服务器不知道该给你什么
            guard auth.isSignedIn else { return }

            await store.start()

            // 开发自检：进主界面之后再退出登录，验证会不会回到登录页
            if DevFlags.devSignOut {
                try? await Task.sleep(for: .seconds(3))
                await auth.signOut()
            }

            // 开发自检：自动加一个好友
            if !DevFlags.addFriendCode.isEmpty {
                try? await store.addFriend(inviteCode: DevFlags.addFriendCode)
            }
            // 开发自检：往第一个会话发一条消息
            if !DevFlags.sendText.isEmpty, let first = store.conversations.first {
                await store.send(DevFlags.sendText, to: first.friend.id)
            }

            // 开发自检：启动并加载完之后，执行一次"删除账号"，验证真的清干净
            if DevFlags.devWipe {
                try? await Task.sleep(for: .milliseconds(500))
                store.deleteEverything()
            }
        }
    }

    // MARK: - 邮件链接跳回来的提示

    /// 告诉用户"邮箱验证成功了"。
    ///
    /// 用一条会自己消失的提示，而不是弹窗：
    ///   · 不打断用户（他刚点完链接，多半正想继续登录）
    ///   · 不强制他做一个"知道了"的动作
    ///   · 而且躲开了上面说的"多个呈现型修饰符互相干扰"的问题
    private func linkBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.mint)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                auth.linkMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(6))
                withAnimation(.snappy) { auth.linkMessage = nil }
            }
        }
    }
}
