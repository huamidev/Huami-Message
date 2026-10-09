import SwiftUI
import PhotosUI

/// 和一个真实好友的聊天页 —— 整个 App 最重要的一屏。
struct ChatView: View {

    let conversation: Conversation

    @Environment(ChatStore.self) private var store

    @Environment(\.dismiss) private var dismiss

    /// 输入框的焦点。
    ///
    /// 【为什么放在聊天页，而不是输入栏内部】
    ///
    /// "点聊天区收起键盘"需要**聊天页**去关掉输入框的焦点。
    /// 焦点状态原来藏在 ChatInputBar 里，外面够不着 ——
    /// 我上次就因为这个绕过去用了 UIKit 的 `resignFirstResponder`，
    /// **结果在 SwiftUI 里根本不管用**：SwiftUI 的焦点不走 UIKit 响应链。
    /// 用户看到的就是"点空白区收不回键盘"。
    ///
    /// 教训：为了"少改几个文件"而绕开正确的做法，代价是功能直接不能用。
    @FocusState private var inputFocused: Bool

    @State private var draft = ""

    /// 记住这次发送用了哪种润色风格。
    /// 发送时会把它标记到消息上，气泡下面就会出现「更得体」这样的小标记 ——
    /// 让用户清楚地知道自己发出去的不是原话。
    @State private var polishedWith: PolishStyle?

    /// 要传给润色面板的数据。
    /// 见下面 PolishRequest 的说明：为什么不能直接让面板去读 draft。
    @State private var polishRequest: PolishRequest?

    @State private var showReportSheet = false
    @State private var showGroupInfo = false
    @State private var showClearConfirm = false

    /// 每条消息对应的判断结果。key 是那条消息的 id。
    ///
    /// 【为什么不再是一份全局的结果】
    ///
    /// 因为要的效果是「判断贴在它读的那条消息下面」。全局一份的话，
    /// 用户往上翻历史时那些卡片就不知道属于哪句话了。
    ///
    /// 不落库：这是对**此刻**的判断，不是一条消息。
    /// 换个说法，它是"读"这段对话，不是"参与"这段对话。
    @State private var analyses: [Message.ID: Analysis] = [:]

    /// 正在判断哪条消息
    @State private var analyzingMessageID: Message.ID?

    @State private var assistantTask: Task<Void, Never>?

    /// 输入框上面的工具栏是不是展开着
    @State private var toolsOpen = DevFlags.openTools

    /// 选照片。
    ///
    /// 用系统的 PhotosPicker 而不是自己写相机/相册界面：
    /// 它自带权限处理、自带"只给选中的那张图"的隐私模式
    ///（用户不用把整个相册都授权给 App），还不用申请相机权限。
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false

    /// 选图失败时要说的话
    @State private var photoError: String?

    /// 点了还没做的功能时的说明
    @State private var voiceNotice: String?

    /// 输入框里选中的位置（给「复制」用）
    @State private var draftSelection: TextSelection?

    /// 是否要确认删除好友
    @State private var showRemoveFriendConfirm = false

    /// 删好友失败时要说的话
    @State private var removeFriendError: String?

    /// **是否自动分析对方的消息。**
    ///
    /// 【这是整个 App 里最需要想清楚的一个开关】
    ///
    /// 打开时：对方每发来一条消息，App 会**自动**把最近 10 条发给 AI ——
    /// 也就是说，**你朋友的消息会在你没有点任何东西的情况下被发出去**，
    /// 而你的朋友从来没有同意过这件事。
    ///
    /// 所以我做了三层控制，而不是简单地"默认开"：
    ///   1. 只分析**你正在看的这个对话**，别的聊天一条都不发
    ///   2. 防抖：对方连发几条时，等他停下来再分析一次（省钱，也更准）
    ///   3. 这里随时能关，关掉之后只有手动点「分析这段对话」才会发送
    ///
    /// 而且隐私说明里**如实写了**这件事 —— 承诺和行为必须一致，
    /// 上一轮刚修过一次"说明和行为对不上"的问题。
    @AppStorage("autoAnalyzeIncoming") private var autoAnalyze = true

    /// 一次判断的完整结果
    struct Analysis: Equatable {
        var status: String?
        var blocks: [DecisionBlock] = []
        var recommendation: String?
        var error: String?
        var sharedCount: Int = 0

        var isDone: Bool { recommendation != nil || error != nil }
    }

    /// 滚动用的锚点。它不是给用户看的，只是给代码一个「滚到这里」的坐标。
    private let bottomAnchor = "bottom"

    /// 顶部锚点。只有开发自检用得上（滚到最顶去验证长列表的行为）。
    private let topAnchor = "top"

    /// 用户现在是不是「贴着底部」。
    ///
    /// 【这个值解决一个真 bug】
    /// 原来只要有新消息就无条件滚到底部。如果用户正在往上翻旧消息，
    /// 就会被**猛地拽到最底下** —— 这在聊天 App 里很恼人：
    /// 读长对话时根本没法往上翻，每来一条消息就被踢回来一次。
    ///
    /// Telegram 和微信都不这样：你往上翻着，它们就安静地待着，
    /// 只在一个小按钮上提醒你「下面有几条新的」。
    @State private var isNearBottom = true

    /// 用户在往上翻的时候，又来了几条新消息。
    /// 用来在「回到最新」按钮上显示数字。
    @State private var unseenCount = 0

    private var messages: [Message] { store.messages(with: conversation.friend.id) }

    /// 加工成「带日期分隔条」的列表
    private var items: [ChatItem] { ChatItem.build(from: messages) }

    /// 拉黑状态直接问 store，而不是读 conversation 里那份可能过期的副本
    private var isBlocked: Bool { store.isBlocked(conversation.friend.id) }

    /// 一条消息的气泡。
    ///
    /// 【为什么要单独提出来】
    ///
    /// 直接写在 body 里的话，那个视图表达式会大到让编译器超时
    /// （报错原文：unable to type-check this expression in reasonable time）。
    /// 把带闭包的那几个参数挪进一个独立函数，编译器就有了明确的类型边界。
    @ViewBuilder
    private func bubble(for message: Message) -> some View {
        MessageBubble(
            message: message,
            sender: senderInfo(for: message),
            onRetry: { Task { await store.retry(message) } },
            onDelete: {
                Haptics.warning()
                withAnimation(.snappy) { store.deleteMessage(message) }
            }
        )
    }

    /// 这条消息是谁发的。一对一返回 nil（那种情况不需要标名字）。
    private func senderInfo(for message: Message) -> GroupMember? {
        guard let id = message.senderID else { return nil }
        return memberByID[id]
    }

    /// 成员表：发消息的人 → 他是谁。群聊里标名字用。
    ///
    /// 从 store 的缓存现算 —— 缓存是"每段会话一次请求"，
    /// 而这个是每帧都要读的，不能在里面发请求。
    private var memberByID: [UUID: GroupMember] {
        guard conversation.friend.kind == .group else { return [:] }
        // ⚠️ 不用 Dictionary(uniqueKeysWithValues:) —— 两个原因：
        //   1. 它遇到重复 key 会**直接崩**（服务端数据万一重复，这里就是闪退）
        //   2. 那个表达式复杂到让 Swift 编译器超时
        //     （报错原文：unable to type-check this expression in reasonable time）
        // 老老实实写个循环，两个问题一起消掉。
        var map: [UUID: GroupMember] = [:]
        for member in store.cachedMembers(of: conversation.friend.id) {
            map[member.id] = member
        }
        return map
    }

    var body: some View {
        // ScrollViewReader 包住整个页面（而不是只包消息列表），
        // 是为了让**底部的「回到最新」按钮也能命令列表滚动** ——
        // 它和列表不在同一层，拿不到里面的 proxy。
        ScrollViewReader { proxy in
            page(proxy: proxy)
        }
    }

    private func page(proxy: ScrollViewProxy) -> some View {
        ZStack {
            // 聊天页是自己压栈进来的，不在 AppPage 里，
            // 所以这里也要单独铺一层背景，否则推入后背景会是系统默认色。
            AppBackground()

            // ── ZStack：消息一直滚到屏幕最底，输入栏那一行浮在上面 ──
            //
            // 这是"和顶栏一样"的做法。我中间走反过一次，记在这里：
            //
            // 用户圈了"输入栏底下冒出半截气泡"，我以为要像顶栏那样**截断**，
            // 就把 ZStack 换成了 VStack，让列表的框到输入栏顶边为止。
            // **方向正好反了。**
            //
            // 顶栏之所以看着干净，不是因为截断，而是因为
            // **按钮浮着、消息从它们下面滚过去，中间没有任何边界**。
            // 用户原话：「改成和顶栏一样，所有元素都是悬浮的，底部没有任何东西」。
            //
            // 所以是 ZStack（叠着），不是 VStack（切开）。
            ZStack(alignment: .bottom) {
                messageList(proxy: proxy)

                VStack(spacing: 0) {
                    // ── 底部渐隐**去掉了** ──
                    //
                    // 这里原来有一条 30 磅的渐隐（透明 → 背景色），
                    // 让消息接近输入栏时"淡淡地没掉"。
                    //
                    // 用户的要求是"学习顶栏的做法" —— 顶栏那边去掉的是
                    // **我们自己铺的一层东西**（标题胶囊的毛玻璃），
                    // 底下对应的就是这一条渐隐。
                    //
                    // 留着它的后果和顶栏一模一样：一条横贯屏幕的色带，
                    // 把消息从中间切断。想"边角柔和"可以靠留白和间距，
                    // 不必再铺一层颜色 —— 铺了就一定有边。

                    VStack(spacing: 6) {
                        // 「回到最新」只在用户往上翻的时候出现 —— 平时不占地方
                        if !isNearBottom {
                            HStack {
                                Spacer()
                                jumpToLatestButton(proxy: proxy)
                            }
                            .padding(.horizontal, 18)
                        }

                        // 小助手的入口**不在这里**了。
                        // 它的结果现在贴在每条消息下面（见 messageList 里那段），
                        // 手动触发放在右上角的菜单里。输入框上方不再摆东西。

                        if toolsOpen {
                            ChatToolbar(
                                hasText: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                onCopy: {
                                    // **选中了就复制选中的，没选中就复制整个输入框。**
                                    // 按了复制却什么都不发生，是最让人困惑的。
                                    let picked = draftSelection?.selectedText(in: draft)
                                    Clipboard.write(picked ?? draft)
                                    toolsOpen = false
                                },
                                onPaste: {
                                    if let pasted = Clipboard.read() {
                                        // 接在原来内容的后面，而不是覆盖掉 ——
                                        // 用户可能已经打了一半
                                        draft += pasted
                                    }
                                    toolsOpen = false
                                },
                                onPhoto: {
                                    toolsOpen = false
                                    showPhotoPicker = true
                                },
                                onPolish: {
                                    toolsOpen = false
                                    guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                        voiceNotice = "先在输入框里写点什么，再来改写。"
                                        return
                                    }
                                    polishRequest = PolishRequest(original: draft)
                                }
                            )
                        }

                        ChatInputBar(
                            focused: $inputFocused,
                            text: $draft,
                            selection: $draftSelection,
                            toolsOpen: toolsOpen,
                            onToggleTools: {
                                withAnimation(.snappy(duration: 0.24)) {
                                    toolsOpen.toggle()
                                }
                            },
                            onPolish: {
                                polishRequest = PolishRequest(original: draft)
                            },
                            onSendVoice: { data, seconds in
                                Task {
                                    await store.sendVoice(data,
                                                          seconds: seconds,
                                                          to: conversation.friend.id)
                                }
                            },
                            onVoiceProblem: { message in
                                // 录音失败（多半是没给权限）必须说出来。
                                // 不说的话用户只会觉得"按了没反应"。
                                voiceNotice = message
                            },
                            onSend: send
                        )
                    }
                    // 面板高度会随着上面两个东西的出现/消失变化，
                    // 不做动画的话它们会"啪"地弹出/消失
                    .animation(.snappy(duration: 0.24), value: isNearBottom)
                    .animation(.snappy(duration: 0.24), value: draft.isEmpty)
                }
                // ── 这里原来铺了一整块不透明的背景，现在去掉了 ──
                //
                // 它当时的作用是"把悬浮标签栏那一块也盖上"——
                // 但**聊天页现在根本不显示标签栏**（进聊天页时它会收走），
                // 所以这块东西已经没有任何存在理由，只是留在那里：
                //   · 让输入栏那一带变成不透明的一块（用户要的是透明）
                //   · 还挡住了那一块底下的消息
                //
                // 教训：注释写清楚了"为什么"，但**那个"为什么"会过期**。
                // 底栏改成自动隐藏之后，这行就该跟着删 —— 没人会想起来。
                //
                // 顺带说明为什么不需要补别的：整页的背景是 AppBackground
                // （一条 ignoresSafeArea 的纯色），底部安全区本来就是它铺满的，
                // 拿掉这行不会露出白边。
            }
        }
        // ── 让我们的手势在屏幕底部优先于系统手势 ──
        //
        // 手机日志里的关键两行（注意**顺序**）：
        //     <0x...> Gesture: System gesture gate timed out.
        //     语音：手指按下
        //
        // 系统手势闸门**先**超时，我们的 onChanged 才触发 ——
        // 也就是说那段等待发生在"手指按下"**之前**，
        // 我们的计时器（从 claimStart 开始算）根本看不到它。
        //
        // 输入栏在最底下，正好是全面屏「home 指示条」那一片，
        // 系统默认在那里优先。按住不动要等它判定"这不是系统手势"，
        // 手指一移动它立刻让路 —— 这就是"滑动秒开、按住不动慢"的机制。
        //
        // ⚠️ 这个修饰符必须挂在**占住屏幕底部的那一整层**上（这一页），
        //    挂在输入栏内部不生效 —— 我先挂在里面试过。
        .defersSystemGestures(on: .bottom)
        // 群聊先把成员拉一次 —— 气泡上标「谁发的」靠的就是这份缓存。
        //
        // 为什么用 .task 而不是在视图里现取：缓存是"每段会话一次请求"，
        // 而气泡是**每帧都要读**的，绝不能在渲染路径里发请求。
        // 绑定 id 是为了换会话时重新拉一次。
        .task(id: conversation.friend.id) {
            let watch = Stopwatch()
            if conversation.friend.kind == .group {
                _ = await store.members(of: conversation.friend.id)
            }
            // 进聊天页要多久 —— 用户说"点进某个聊天有点卡"，
            // 这一行把它变成数字。相邻两行日志一减就是耗时，
            // 不用再靠感觉描述。
            AppLog.info(.data, "进聊天页：\(conversation.friend.displayName)｜"
                        + "本地已有 \(store.messages(with: conversation.friend.id).count) 条消息｜"
                        + "准备耗时 \(Stopwatch.format(watch.milliseconds))")
        }
        .navigationTitle(conversation.friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // 导航栏也做成毛玻璃 —— 消息从它下面滚过去时，
        // 会透出一层模糊的颜色在动。这种「边缘也在呼吸」的细节很值钱。
        // 顶栏**不做成一条不透明的横条**（照 Telegram 的做法）。
        //
        // 原来写的是 .toolbarBackground(.ultraThinMaterial) + .visible：
        // 那会画一条贯穿整屏的毛玻璃，内容滚到它下面时被"切断"，
        // 看起来像两个割裂的区域。
        //
        // 改成 hidden 之后，**顶栏本身什么都不画**，
        // 只有浮在上面的那几个元素（返回、名字胶囊、菜单）。
        // 消息从它们底下穿过去 —— 这才是一个整体的对话界面。
        .toolbarBackground(.hidden, for: .navigationBar)
        // iOS 18 起这个修饰符改名了；两个都写，哪个生效都行。
        // （老的那个在 iOS 26 上对某些样式不完全生效 —— 用户截图里
        //   顶上仍有一条比背景略亮的横带，就是它。）
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        // 进聊天页就**把底栏藏起来**（微信、Telegram 都是这样）。
        //
        // 【为什么要专门写这一行】
        //
        // 在 TabView 里用 NavigationStack 推进去的页面，底栏**默认是一直挂着的** ——
        // 系统不知道你希望它消失。
        //
        // 藏起来不只是为了好看：聊天时底下那条栏会**压住最后几条消息**，
        // 而且输入框和它挤在一起，手指容易点错。藏掉之后整屏都是对话。
        //
        // ⚠️ 这个修饰符要写在**被推进去的那个页面**上，不要写在 TabView 上 ——
        // 写在 TabView 上会连根一起藏掉，返回之后也回不来。
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // 名字装在**一个胶囊里**，浮在对话上面。
            //
            // 为什么不用系统默认的标题：系统标题是画在导航栏那一层上的，
            // 要么跟着那条横条一起显示、要么一起消失。
            // 装进胶囊之后它是一个**独立的小牌子**，
            // 底下的消息滚过去时从它两边经过 —— Telegram 就是这么做。
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(conversation.friend.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                // 名字**不加底** —— 直接浮在对话上面。
                //
                // 原来这里套了一层 .regularMaterial（毛玻璃胶囊），
                // 用户的原话是"顶栏也不要半透明，直接透明"。
                //
                // 去掉之后名字是"飘在消息上"的 —— 也正是 Telegram 的样子：
                // 消息从它两边/下面滚过去，而不是被一条横带切开。
            }

            ToolbarItem(placement: .topBarTrailing) { manageMenu }
        }
        .safeAreaInset(edge: .top) {
            if isBlocked { blockedBanner }
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupInfoView(conversation: conversation) {
                // 退群之后把聊天页也关掉 ——
                // 不然用户还停在一个自己已经不在的群里继续发消息
                dismiss()
            }
            .environment(store)
        }
        .sheet(item: $polishRequest) { request in
            PolishSheet(original: request.original) { picked, style in
                // 选中的版本只是**填回输入框**，不会自动发出去。
                // 你还有机会改一改再发。
                // 发消息是不可撤销的动作，绝不能让 AI 替你按下发送键。
                draft = picked
                polishedWith = style
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Theme.surface)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(friend: conversation.friend) { reason, note in
                store.report(conversation.friend.id, reason: reason, note: note)
            }
            .presentationBackground(Theme.surface)
            .presentationCornerRadius(30)
        }
        // 删除是不可撤销的，必须再问一次 —— 这是"防手滑"的基本礼貌
        .confirmationDialog("清空和 \(conversation.friend.displayName) 的聊天记录？",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空聊天记录", role: .destructive) {
                Haptics.warning()
                withAnimation(.snappy) { store.clearMessages(with: conversation.friend.id) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("消息会从你的手机上永久删除，无法恢复。")
        }
        .onAppear {
            // ⚠️ **不要在这里同步写数据库。**
            //
            // markRead → setUnread → local.setUnread 是一次**同步的**
            // SwiftData 写入 + commit。而 onAppear 正好发生在**推入动画中间** ——
            // 主线程被这一步占住，动画就会顿一下。
            //
            // 清个未读红点完全不急，晚 0.4 秒没有任何人能察觉，
            // 但省下来的是转场那几帧。用户报的"点进聊天有点卡"，
            // 这是嫌疑之一（不一定是全部，日志会告诉我们）。
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                store.markRead(conversation.friend.id)
            }
        }
        // 开发用：
        //   -openPolish 1  自动填一句示例并打开润色面板
        //   -autoSend 1    自动发一条消息（配合 -failSend 1 可以验证失败和重试）
        // 正常启动都不会触发。
        .task {
            // ── 打开会话时确保真的停在最新一条 ──
            //
            // ⚠️ 只靠 .defaultScrollAnchor(.bottom) 在长列表里会差一点点：
            //    LazyVStack 一开始只"实现"了一部分内容，锚到底是按**当时**的
            //    内容高度算的；随着更多内容被实现，总高度变大，位置就偏了 ——
            //    表现是"打开一个长对话，最后两条看不见"（我在长列表自检里发现的）。
            //    所以这里等布局稳定后再补一次，而且**不加动画**，
            //    否则用户会看到打开瞬间画面"唰"地跳一下。
            try? await Task.sleep(for: .milliseconds(280))
            proxy.scrollTo(bottomAnchor, anchor: .bottom)

            if DevFlags.openPolish, draft.isEmpty {
                // ⚠️ 必须等一下再打开。
                //
                // 因为启动时登录用的 fullScreenCover 还盖在最上面 ——
                // 在那个覆盖还在的时候请求弹窗会被**无声吞掉**：不报错、
                // 不警告，就是什么都不显示。更坑的是**弹窗里的 .task 照样会跑**，
                // 所以 AI 请求发出去了、钱花了，用户却什么都看不见。
                //
                // （同一类问题我在"加好友"页也踩过一次。）
                try? await Task.sleep(for: .seconds(2))

                // 用同一个常量同时喂给输入框和面板，避免"读回来的值不一样"
                let demo = "你昨天怎么没来？大家都等你很久了，你这样不太好吧。"
                draft = demo
                polishRequest = PolishRequest(original: demo)
            }

            if DevFlags.blockChat {
                store.setBlocked(true, for: conversation.friend.id)
            }

            if DevFlags.openReport {
                showReportSheet = true
            }

            if DevFlags.openAssistant {
                analyzeLatest()
            }

            // 危险操作的自检：删除整个会话。
            // 删除是 SwiftData 最容易出问题的地方（比如把好友删了、
            // 消息却留在库里变成永远看不见的垃圾数据），所以它必须被真的测一遍。
            if DevFlags.devDeleteChat {
                store.deleteConversation(conversation.friend.id)
            }

            // 开发自检：先滚到最顶，再发一条消息。
            // 正确表现 = 画面**停在原地**，右下角出现「回到最新 ①」。
            // 如果画面被拽到了底部，说明修复没生效。
            if DevFlags.verifyScrollFix {
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(topAnchor, anchor: .top)   // 不加动画，立刻到位
                try? await Task.sleep(for: .seconds(1))
                await store.send("滚动自检 \(Date().formatted(date: .omitted, time: .standard))",
                                 to: conversation.friend.id)
            }

            if DevFlags.autoSend {
                // 带上时间戳，这样重启后能一眼认出"这条是上一次发的"，
                // 用来验证消息真的存进了本地数据库。
                let stamp = Date().formatted(date: .omitted, time: .standard)
                await store.send("自动测试消息 \(stamp)", to: conversation.friend.id)
            }
        }
    }

    // MARK: - 右上角的管理菜单
    //
    // 拉黑和举报放在这里，而不是藏在"设置 → 隐私 → 更多"里。
    // 审核和用户都需要能在**两步之内**找到它们。

    private var manageMenu: some View {
        Menu {
            if conversation.friend.kind == .group {
                Button {
                    Haptics.tap()
                    showGroupInfo = true
                } label: {
                    Label("群聊信息", systemImage: "person.3")
                }
                Divider()
            }

            Button {
                Haptics.tap()
                analyzeLatest()
            } label: {
                Label("分析这段对话", systemImage: "sparkles")
            }

            // 这个开关放在菜单里而不是设置里，是刻意的：
            // 用户看到"AI 自动读了对方的消息"时，最想知道的就是**怎么关掉它**，
            // 而那一刻他正在这个页面上。
            Toggle(isOn: $autoAnalyze) {
                Label("自动分析对方的消息", systemImage: "wand.and.stars")
            }

            if autoAnalyze {
                Text("打开时，对方每发来一条消息都会把最近 10 条发给 AI 服务商")
            }

            Divider()

            Button {
                // 拉黑是"重"动作，用警告震动，和轻点的发送明确区分开
                Haptics.warning()
                withAnimation(.snappy) {
                    store.setBlocked(!isBlocked, for: conversation.friend.id)
                }
            } label: {
                Label(isBlocked ? "取消拉黑" : "拉黑",
                      systemImage: isBlocked ? "hand.raised.slash" : "hand.raised")
            }

            Button {
                showReportSheet = true
            } label: {
                Label("举报", systemImage: "exclamationmark.bubble")
            }

            Divider()

            // 「删除好友」和下面的「清空聊天记录」是**两件不同的事**，
            // 所以中间隔一条线：
            //   删除好友     = 解除关系，两边都不再是好友
            //   清空聊天记录 = 只清我本地的记录，还是好友
            // 用户搞混的代价很大 —— 一个是误删好友，一个是以为只清了记录。
            Button(role: .destructive) {
                showRemoveFriendConfirm = true
            } label: {
                Label("删除好友", systemImage: "person.badge.minus")
            }

            Divider()

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清空聊天记录", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    /// 拉黑之后的提示条。
    /// 必须让用户**一直看得见**自己被拉黑状态，否则他会奇怪"为什么对方不理我"。
    private var blockedBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12))
            Text("已拉黑 \(conversation.friend.displayName)，你不会再收到他的消息")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("取消") {
                withAnimation(.snappy) {
                    store.setBlocked(false, for: conversation.friend.id)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .foregroundStyle(Theme.danger)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(hex: 0xFDECEC))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.8)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - 小助手

    /// 开始一次判断，结果**贴在指定的那条消息下面**。
    private func runAssistant(_ intent: AssistantIntent, attachTo messageID: Message.ID) {
        assistantTask?.cancel()
        Haptics.tap()

        let context = store.assistantContext(
            for: conversation.friend.id,
            friendName: conversation.friend.displayName
        )

        // 这次到底发了多少条，如实显示给用户 ——
        // 隐私承诺不能只写在政策里，得在用户眼前成立
        withAnimation(.snappy(duration: 0.25)) {
            analyses[messageID] = Analysis(status: "正在读这段对话",
                                           sharedCount: context.messages.count)
            analyzingMessageID = messageID
        }

        assistantTask = Task {
            do {
                for try await event in AppServices.makeAIService()
                    .advise(context: context, intent: intent) {
                    if Task.isCancelled { return }
                    switch event {
                    case .status(let text):
                        analyses[messageID]?.status = text

                    case .block(let block):
                        withAnimation(.snappy(duration: 0.3)) {
                            analyses[messageID]?.blocks.append(block)
                        }

                    case .recommendation(let text):
                        withAnimation(.snappy(duration: 0.3)) {
                            analyses[messageID]?.recommendation = text
                            analyses[messageID]?.status = nil
                        }
                    }
                }
            } catch {
                if Task.isCancelled { return }
                // 失败必须说出来。真网络一定会出问题，
                // 只留一个永远转不完的"正在想…"是最让人火大的。
                withAnimation(.snappy(duration: 0.3)) {
                    analyses[messageID]?.status = nil
                    analyses[messageID]?.error = (error as? LocalizedError)?.errorDescription
                        ?? "小助手这次没成功，等一下再试。"
                }
                Haptics.warning()
                return
            }
            guard !Task.isCancelled else { return }
            analyses[messageID]?.status = nil
            analyzingMessageID = nil
            Haptics.success()
        }
    }

    /// 对方发来新消息时，自动分析一次。
    ///
    /// 【为什么要防抖】
    ///
    /// 对方常常连着发好几条（「在吗」「那个事」「你怎么不说话」）。
    /// 每条都分析的话：又费钱、又会在界面上刷出一堆卡片。
    /// **等他停下来一秒多再分析**，既省又好读。
    private func autoAnalyzeIfNeeded() {
        guard autoAnalyze else { return }
        guard let last = messages.last, last.sender == .friend else { return }
        guard analyses[last.id] == nil else { return }   // 分析过就不重复

        let target = last.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))

            // 等完之后如果又来了新消息，交给新的一次去处理
            guard messages.last?.id == target else { return }
            guard autoAnalyze else { return }
            guard analyses[target] == nil else { return }

            runAssistant(.reply, attachTo: target)
        }
    }

    /// 手动分析最后一条消息（菜单里的「分析这段对话」）
    private func analyzeLatest() {
        guard let last = messages.last else { return }
        runAssistant(.reply, attachTo: last.id)
    }

    // MARK: - 消息列表

    private func messageList(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // 看不见的顶部锚点（开发自检用来滚到最顶上）
                Color.clear.frame(height: 1).id(topAnchor)


                ForEach(items) { item in
                    switch item {
                    case .daySeparator(let date):
                        DaySeparatorView(date: date)
                            .id(item.id)

                    case .message(let message):
                        VStack(alignment: .leading, spacing: 8) {
                            bubble(for: message)

                            // 判断贴在**它读的那条消息**下面 ——
                            // 这样往上翻历史时，每张卡片都还知道自己说的是哪句话。
                            if let analysis = analyses[message.id] {
                                DecisionCardsView(
                                    status: analysis.status,
                                    blocks: analysis.blocks,
                                    recommendation: analysis.recommendation,
                                    error: analysis.error,
                                    sharedMessageCount: analysis.sharedCount
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                            }
                        }
                        .id(item.id)
                    }
                }

                // 一个看不见的锚点。滚到它 = 滚到最底部。
                Color.clear.frame(height: 1).id(bottomAnchor)

                // 给悬浮的输入栏和小助手按钮留出空间，
                // 否则最后一条消息会被它们盖住
                Color.clear.frame(height: 130)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            // 让新消息真正「弹」进来。
            //
            // ⚠️ MessageBubble 里写了 .transition，但**只定义 transition
            //    而没有动画驱动，等于没写** —— 它一直没生效过。
            //    必须有一个 .animation(_:value:)（或包在 withAnimation 里）
            //    才会真的播出来。这一行就是那个"驱动"。
            .animation(.snappy(duration: 0.26), value: messages.count)
        }
        .scrollIndicators(.hidden)
        // 手指往下拖就把键盘收起来 —— iOS 上大家都习惯这个手势，
        // 少了它会被觉得「不是原生 App」
        // .immediately：**一开始划就收**。
        //
        // 原来用的 .interactively 是"键盘跟着手指走" ——
        // 用户原话是"下滑的操作感受也很烂"：粘手、还占着屏幕高度，
        // 划到一半松手它又弹回来。聊天列表不需要这种跟手感。
        // 84 磅那个手填的留白删掉了 —— 换成 VStack 之后不需要了：
        // 列表的框本身就到输入栏顶边为止，高度由布局算，不用估。
        // 关掉 iOS 26 起"内容滚到边缘自动糊一层"的效果。
        //
        // 用户说的"顶上那条半透明的东西"就是它 ——
        // 前两次改的（toolbarBackground / 标题胶囊）都不是它。
        // API 名是从 SDK 里搜出来的，不是猜的。
        .scrollEdgeEffectHidden(true, for: .all)
        // ── 滚到底时给输入栏留出位置 ──
        //
        // 消息是**浮在输入栏下面**滚过去的（这是之前特意做的效果），
        // 所以"滚到底"= 最后一条会被输入栏压住一半。
        // 用户要的是「比输入框稍微高一点」。
        //
        // contentMargins 给**滚动内容**加下边距：滚到底时最后一条
        // 停在离底 80 磅的地方，正好在输入栏（约 62 磅高）上方留一点空隙。
        // 手动往上翻的时候，消息照样能从输入栏下面经过 —— 这个效果没丢。
        //
        // 80 是"输入栏高度 + 一点空隙"估的。输入栏高度写死在
        // ChatInputBar.controlHeight(=40)，加上它自己的内边距大约 62。
        .contentMargins(.bottom, 80, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        // ── 点聊天区收起键盘 ──
        //
        // 用 simultaneousGesture 而不是 gesture：
        // 后者会**抢走**子视图的点击（图片气泡点开大图、长按菜单都会失灵）。
        // simultaneous 是"我听到了，但不拦着别人"。
        //
        .simultaneousGesture(
            TapGesture().onEnded {
                // 必须改 @FocusState —— resignFirstResponder 在 SwiftUI 里不生效
                withAnimation(.snappy(duration: 0.2)) { inputFocused = false }
            }
        )
        // 一进来就停在最新一条，而不是从最顶上开始。
        // 这一个小设置直接决定了「打开会话是不是顺手」。
        .defaultScrollAnchor(.bottom)
        // 实时知道用户是不是贴着底部。
        // onScrollGeometryChange 是 iOS 18 的新能力，能在滚动过程中读到
        // 内容尺寸和当前可视区域 —— 这是实现"别把用户拽走"的关键信息。
        // 空会话提示放在**覆盖层**而不是滚动内容里。
        //
        // 为什么：内容比屏幕短的时候，`.defaultScrollAnchor(.bottom)` 会把内容压到底部，
        // 于是提示文字正好落在底部面板底下被盖住（我第一版就是这样，
        // "说点什么吧"那行完全看不见）。
        // 做成覆盖层并留出底部空间，它才会出现在真正空着的那块地方。
        .overlay {
            if messages.isEmpty {
                emptyChatHint
                    .allowsHitTesting(false)
            }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            // 距离底部 140 磅以内就算「贴着底部」。
            // 留这段余量，是因为列表末尾有一段专门给输入栏的空白。
            geometry.contentSize.height - geometry.visibleRect.maxY < 140
        } action: { _, nearBottom in
            isNearBottom = nearBottom
            // 一旦回到最底下，新消息就算都看过了
            if nearBottom { unseenCount = 0 }
        }
        .alert("图片", isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button("好") { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
        .alert("还没做", isPresented: Binding(
            get: { voiceNotice != nil },
            set: { if !$0 { voiceNotice = nil } }
        )) {
            Button("好") { voiceNotice = nil }
        } message: {
            Text(voiceNotice ?? "")
        }
        .confirmationDialog("删除好友？",
                            isPresented: $showRemoveFriendConfirm,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    do {
                        try await store.removeFriend(conversation.friend.id)
                        dismiss()
                    } catch {
                        // 失败必须说出来 —— 否则用户以为删了，下次同步他又冒出来
                        removeFriendError = (error as? LocalizedError)?.errorDescription
                            ?? "没删掉，等一下再试。"
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你们会互相从好友列表里消失，聊天记录也会清掉。\n\n如果只是不想收他的消息，用「拉黑」。")
        }
        .alert("删除好友", isPresented: Binding(
            get: { removeFriendError != nil },
            set: { if !$0 { removeFriendError = nil } }
        )) {
            Button("好") { removeFriendError = nil }
        } message: {
            Text(removeFriendError ?? "")
        }
        .task {
            // 开发自检：N 秒后自动返回，用来拍过渡动画
            guard DevFlags.popAfter > 0 else { return }
            try? await Task.sleep(for: .seconds(DevFlags.popAfter))
            dismiss()
        }
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $pickedPhoto,
                      matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                defer { pickedPhoto = nil }

                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let compressed = image.compressedForChat() else {
                    // 读不出来就明说。静默失败会让用户以为发出去了。
                    photoError = "这张图片读不出来，换一张试试。"
                    return
                }
                await store.sendImage(compressed, to: conversation.friend.id)
            }
        }
        .onChange(of: messages.count) { oldCount, newCount in
            // 对方来了新消息 → 自动分析一次（内部会判断开关和防抖）
            autoAnalyzeIfNeeded()

            if isNearBottom {
                withAnimation(.snappy(duration: 0.32)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            } else {
                // 用户正在读旧消息 —— 只记个数，绝不动他的位置
                unseenCount += max(0, newCount - oldCount)
            }
        }
        // 小助手每冒出一个方块，就往下滚一点让它露出来。
        // 不滚的话方块会长在屏幕外面，用户以为它卡住了。
        // 卡片一个个冒出来时跟着往下滚一点。
        // 用"所有已分析消息的方块总数"当信号 —— 比盯某一条更稳，
        // 因为分析可能挂在任意一条消息上。
        .onChange(of: analyses.values.reduce(0) { $0 + $1.blocks.count }) { _, _ in
            withAnimation(.snappy(duration: 0.3)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
        // 拉黑提示条出现/消失时，聊天区域的高度会变。
        // 不重新对齐的话，最后一条消息会被输入栏挡住 —— 这个细节很小，
        // 但"最后一条看不见"是用户一眼就能察觉的毛病。
        .onChange(of: isBlocked) { _, _ in
            withAnimation(.snappy(duration: 0.3)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    /// 新加的好友还没有任何消息时显示。
    /// 不处理的话这里就是一整屏空白 —— 看起来像 App 坏了。
    private var emptyChatHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.wave")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textTertiary)
            Text("你们还没有聊过")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("说点什么吧")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // 往上抬，躲开底部的小助手方块和输入栏
        .padding(.bottom, 190)
    }

    // MARK: - 「回到最新」

    /// 只在用户往上翻旧消息时出现的按钮。
    ///
    /// 带一个数字，告诉他下面还压着几条没看。
    /// 这件小事让「往上翻」变成一个**安全的动作**：
    /// 你知道新消息不会跑掉，界面也不会把你踢回去。
    @ViewBuilder
    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        if !isNearBottom {
            Button {
                Haptics.tap()
                withAnimation(.snappy(duration: 0.35)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
                unseenCount = 0
            } label: {
                HStack(spacing: 5) {
                    if unseenCount > 0 {
                        Text("\(unseenCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent, in: Capsule())
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }

    // MARK: - 发送

    private func send() {
        let text = draft
        let style = polishedWith

        // 按下发送的那一下给一个轻震。
        // 这是"手感"里最便宜也最有效的一环 —— 用户注意不到它，
        // 但少了它，界面会显得"飘"。
        Haptics.tap()

        // ① 立刻清空输入框 —— 不等网络。
        draft = ""
        polishedWith = nil

        // ② 真正发送交给 store 在后台做。
        //    注意这里没有 await：界面不等它，
        //    消息会由 store 先插进列表再跟服务器对账。
        Task {
            await store.send(text, to: conversation.friend.id, polishedWith: style)
        }
    }
}

/// 要润色的原文 + 弹窗的"开关"，打包成一个整体。
///
/// 为什么要这么绕？我踩过坑：
/// 原来写的是 `.sheet(isPresented: $showPolishSheet) { PolishSheet(original: draft) }`，
/// 结果弹出来的面板里原文是**空的** —— 内容闭包读到的是过期的 draft。
///
/// 改成 `.sheet(item:)` 之后，原文作为"这一份请求"的数据一起被带进去，
/// 值的来源就唯一了，不依赖任何读取时机。
///
/// 这是个通用经验：**要传给弹窗的数据，应该和"打开弹窗"这个动作绑在一起，
/// 而不是让弹窗自己在某个时刻去读外面的状态。**
struct PolishRequest: Identifiable {
    let id = UUID()
    let original: String
}

