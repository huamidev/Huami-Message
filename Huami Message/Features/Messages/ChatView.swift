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
    private struct PolishRequest: Identifiable {
        let id = UUID()
        let original: String
    }

    @State private var polishRequest: PolishRequest?

    /// 滚动用的锚点。它不是给用户看的，只是给代码一个「滚到这里」的坐标。
    private let bottomAnchor = "bottom"

    private var messages: [Message] { store.messages(with: conversation.friend.id) }

    var body: some View {
        ZStack {
            // 聊天页是自己压栈进来的，不在 GlassPage 里，
            // 所以这里也要单独铺一层极光背景，否则推入后背景会变黑。
            AuroraBackground()

            ZStack(alignment: .bottom) {
                messageList

                ChatInputBar(
                    text: $draft,
                    onPolish: { polishRequest = PolishRequest(original: draft) },
                    onSend: send
                )
            }
        }
        .navigationTitle(conversation.friend.name)
        .navigationBarTitleDisplayMode(.inline)
        // 导航栏也做成毛玻璃 —— 消息从它下面滚过去时，
        // 会透出一层模糊的颜色在动。这种「边缘也在呼吸」的细节很值钱。
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $polishRequest) { request in
            PolishSheet(original: request.original) { picked, style in
                // 选中的版本只是**填回输入框**，不会自动发出去。
                // 你还有机会改一改再发。
                // 发消息是不可撤销的动作，绝不能让 AI 替你按下发送键。
                draft = picked
                polishedWith = style
            }
            .presentationDetents([.medium, .large])
            // 让弹窗本身就是一块毛玻璃，而不是一块死白/死黑的板子
            .presentationBackground(.regularMaterial)
            .presentationCornerRadius(30)
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

            if DevFlags.autoSend {
                // 带上时间戳，这样重启后能一眼认出"这条是上一次发的"，
                // 用来验证消息真的存进了本地数据库。
                let stamp = Date().formatted(date: .omitted, time: .standard)
                await store.send("自动测试消息 \(stamp)", to: conversation.friend.id)
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message) {
                            // 点"重试"：把这条重新送出去
                            Task { await store.retry(message) }
                        }
                        .id(message.id)
                    }

                    // 一个看不见的锚点。滚到它 = 滚到最底部。
                    Color.clear.frame(height: 1).id(bottomAnchor)

                    // 给悬浮的输入栏留出空间，否则最后一条消息会被它盖住
                    Color.clear.frame(height: 84)
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
