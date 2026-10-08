import SwiftUI

/// 和一个真实好友的聊天页 —— 整个 App 最重要的一屏。
struct ChatView: View {

    let conversation: Conversation

    @Environment(ChatStore.self) private var store

    @State private var draft = ""

    /// 记住这次发送用了哪种润色风格。
    /// 发送时会把它标记到消息上，气泡下面就会出现「更得体」这样的小标记 ——
    /// 让用户清楚地知道自己发出去的不是原话。
    @State private var polishedWith: PolishStyle?

    /// 要传给润色面板的数据。
    /// 见下面 PolishRequest 的说明：为什么不能直接让面板去读 draft。
    @State private var polishRequest: PolishRequest?

    @State private var showReportSheet = false
    @State private var showClearConfirm = false

    /// 要交给小助手的上下文。
    /// 和润色一样用 `.sheet(item:)` 而不是 `.sheet(isPresented:)` ——
    /// 要发给弹窗的数据，必须和"打开弹窗"这个动作绑在一起，
    /// 不能让弹窗自己在某个时刻去读外面的状态（那个坑我踩过。）
    @State private var assistantRequest: AssistantRequest?

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

            ZStack(alignment: .bottom) {
                messageList(proxy: proxy)

                VStack(spacing: 0) {
                    // ── 底部渐隐 ──
                    // 让消息在接近输入栏时"淡淡地没掉"，而不是被一条硬边切断。
                    // Telegram / 微信都是这么做的。
                    LinearGradient(
                        colors: [Theme.background.opacity(0), Theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 30)
                    .allowsHitTesting(false)   // 别挡住手指滚动

                    VStack(spacing: 6) {
                        // 「回到最新」只在用户往上翻的时候出现 —— 平时不占地方
                        if !isNearBottom {
                            HStack {
                                Spacer()
                                jumpToLatestButton(proxy: proxy)
                            }
                            .padding(.horizontal, 18)
                        }

                        // ── 小助手的入口 ──
                        // 常驻在这里，不做"打字时隐藏"。
                        //
                        // 我试过在输入框有字时把它收起来（理由是"你已经在打字了，
                        // 说明你知道要说什么"），但那样会让面板高度忽高忽低，
                        // 列表位置跟着跳 —— 为了省 80 磅换来一次跳动，不划算。
                        //
                        // 常驻还有一个好处：它的存在本身就在提醒用户
                        // "这里有个东西能帮你"。
                        assistantQuickBox
                            .padding(.horizontal, 12)

                        ChatInputBar(
                            text: $draft,
                            onPolish: { polishRequest = PolishRequest(original: draft) },
                            onSend: send
                        )
                    }
                    // 面板高度会随着上面两个东西的出现/消失变化，
                    // 不做动画的话它们会"啪"地弹出/消失
                    .animation(.snappy(duration: 0.24), value: isNearBottom)
                    .animation(.snappy(duration: 0.24), value: draft.isEmpty)
                }
                // ── 把悬浮标签栏那一块也盖上 ──
                //
                // ⚠️ 这里必须用 background 的 ignoresSafeAreaEdges 参数，
                //    **不能**靠 .ignoresSafeArea()。
                //    我试过后者：在 ZStack 的底部对齐子视图里它根本不生效 ——
                //    用红色探针量出来，渐隐层的底边老老实实停在安全区底边，
                //    下面还有 74 磅露着消息。
                .background(Theme.background, ignoresSafeAreaEdges: .bottom)
            }
        }
        .navigationTitle(conversation.friend.name)
        .navigationBarTitleDisplayMode(.inline)
        // 导航栏也做成毛玻璃 —— 消息从它下面滚过去时，
        // 会透出一层模糊的颜色在动。这种「边缘也在呼吸」的细节很值钱。
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { manageMenu }
        }
        .safeAreaInset(edge: .top) {
            if isBlocked { blockedBanner }
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
        .sheet(item: $assistantRequest) { request in
            AssistantSheet(context: request.context, intent: request.intent) { reply in
                // 和润色一样：只填回输入框，不自动发送。
                draft = reply
            }
            .presentationDetents([.large])
            .presentationBackground(Theme.surface)
            .presentationCornerRadius(30)
        }
        // 删除是不可撤销的，必须再问一次 —— 这是"防手滑"的基本礼貌
        .confirmationDialog("清空和 \(conversation.friend.name) 的聊天记录？",
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
            store.markRead(conversation.friend.id)
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
                assistantRequest = AssistantRequest(
                    context: store.assistantContext(
                        for: conversation.friend.id,
                        friendName: conversation.friend.name
                    ),
                    intent: .reply
                )
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
            Text("已拉黑 \(conversation.friend.name)，你不会再收到他的消息")
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

    // MARK: - 小助手的入口

    /// 小助手的入口：一个**小方块，里面直接摆几个具体问题**。
    ///
    /// 【为什么不做成"一个图标按钮，点开再选"】
    ///
    /// 想找小助手的人，心里其实已经有一个具体问题了：
    /// "他这话到底什么意思"、"我该怎么回"、"帮我起个头"。
    /// 与其让他点开一个面板、再打字描述需求，不如把问题直接摆在面前 ——
    /// **少一步，而且不用组织语言**。
    ///
    /// 上面那行小字一直在，用户点之前就知道会发生什么 —— 这是知情同意的前提。
    private var assistantQuickBox: some View {
        VStack(alignment: .leading, spacing: 7) {

            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("小助手 · 点选项会把最近 \(AssistantContext.recentLimit) 条消息发给 AI")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                ForEach(AssistantIntent.allCases) { intent in
                    Button {
                        Haptics.tap()
                        assistantRequest = AssistantRequest(
                            context: store.assistantContext(
                                for: conversation.friend.id,
                                friendName: conversation.friend.name
                            ),
                            intent: intent
                        )
                    } label: {
                        Text(intent.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .card(radius: 16)
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
                        MessageBubble(
                            message: message,
                            onRetry: { Task { await store.retry(message) } },
                            onDelete: {
                                Haptics.warning()
                                withAnimation(.snappy) { store.deleteMessage(message) }
                            }
                        )
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
        .scrollDismissesKeyboard(.interactively)
        // 一进来就停在最新一条，而不是从最顶上开始。
        // 这一个小设置直接决定了「打开会话是不是顺手」。
        .defaultScrollAnchor(.bottom)
        // 实时知道用户是不是贴着底部。
        // onScrollGeometryChange 是 iOS 18 的新能力，能在滚动过程中读到
        // 内容尺寸和当前可视区域 —— 这是实现"别把用户拽走"的关键信息。
        .onScrollGeometryChange(for: Bool.self) { geometry in
            // 距离底部 140 磅以内就算「贴着底部」。
            // 留这段余量，是因为列表末尾有一段专门给输入栏的空白。
            geometry.contentSize.height - geometry.visibleRect.maxY < 140
        } action: { _, nearBottom in
            isNearBottom = nearBottom
            // 一旦回到最底下，新消息就算都看过了
            if nearBottom { unseenCount = 0 }
        }
        .onChange(of: messages.count) { oldCount, newCount in
            if isNearBottom {
                withAnimation(.snappy(duration: 0.32)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            } else {
                // 用户正在读旧消息 —— 只记个数，绝不动他的位置
                unseenCount += max(0, newCount - oldCount)
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

/// 交给小助手的上下文 + 弹窗开关，打包成一个整体。
/// 理由和上面的 PolishRequest 完全一样。
struct AssistantRequest: Identifiable {
    let id = UUID()
    let context: AssistantContext
    let intent: AssistantIntent
}
