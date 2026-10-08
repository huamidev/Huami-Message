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

    private var messages: [Message] { store.messages(with: conversation.friend.id) }

    /// 加工成「带日期分隔条」的列表
    private var items: [ChatItem] { ChatItem.build(from: messages) }

    /// 拉黑状态直接问 store，而不是读 conversation 里那份可能过期的副本
    private var isBlocked: Bool { store.isBlocked(conversation.friend.id) }

    var body: some View {
        ZStack {
            // 聊天页是自己压栈进来的，不在 AppPage 里，
            // 所以这里也要单独铺一层背景，否则推入后背景会是系统默认色。
            AppBackground()

            ZStack(alignment: .bottom) {
                messageList

                VStack(spacing: 6) {
                    // ── 小助手的入口 ──
                    // 悬浮在输入栏正上方、靠右。
                    // 它不再是一个底部 Tab：一个"帮你看懂这段对话"的助手，
                    // 就该待在对话发生的这个界面里，而不是让用户复制来复制去。
                    HStack {
                        Spacer()
                        assistantButton
                    }
                    .padding(.horizontal, 18)

                    ChatInputBar(
                        text: $draft,
                        onPolish: { polishRequest = PolishRequest(original: draft) },
                        onSend: send
                    )
                }
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
            AssistantSheet(context: request.context) { reply in
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
                    )
                )
            }

            // 危险操作的自检：删除整个会话。
            // 删除是 SwiftData 最容易出问题的地方（比如把好友删了、
            // 消息却留在库里变成永远看不见的垃圾数据），所以它必须被真的测一遍。
            if DevFlags.devDeleteChat {
                store.deleteConversation(conversation.friend.id)
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

    /// 悬浮的小助手按钮。
    ///
    /// 为什么是一个带字的小胶囊，而不是一个纯图标按钮：
    /// 它和输入栏左边那个 ✨（润色）**功能完全不同** ——
    /// 一个改你打的这句话，一个帮你想整件事该怎么办。
    /// 两个图标长得一样、又挨得近，用户一定会搞混。
    /// 写上「小助手」三个字，这个歧义就没了。
    private var assistantButton: some View {
        Button {
            assistantRequest = AssistantRequest(
                context: store.assistantContext(
                    for: conversation.friend.id,
                    friendName: conversation.friend.name
                )
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("小助手")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Theme.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
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
            }
            .scrollIndicators(.hidden)
            // 手指往下拖就把键盘收起来 —— iOS 上大家都习惯这个手势，
            // 少了它会被觉得「不是原生 App」
            .scrollDismissesKeyboard(.interactively)
            // 一进来就停在最新一条，而不是从最顶上开始。
            // 这一个小设置直接决定了「打开会话是不是顺手」。
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.snappy(duration: 0.35)) {
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
    }

    // MARK: - 发送

    private func send() {
        let text = draft
        let style = polishedWith

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
}
