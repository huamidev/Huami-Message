import SwiftUI

/// 悬浮在底部的输入栏。
///
/// 【布局照 Telegram】
///
///     (📎)  [ (头像) 说点什么…  ✨ ]  (🎤)
///
/// 左边一个圆形的回形针（附件），中间一个长胶囊，
/// 右边一个圆形的麦克风。右边那个**有字的时候会变成发送**。
///
/// 几个决定：
///
/// · **回形针而不是"+"**：加号太抽象，用户不知道点开是什么。
///   回形针是"附带点东西"的通用符号，一眼就懂。
///
/// · **头像放在输入框里面**：它不承担任何功能，只是一个"这是你在说话"的
///   视觉锚点。放在框里不占额外位置，也不抢注意力。
///
/// · **麦克风和发送共用一个位置**：和之前"加号/发送二选一"是同一个道理 ——
///   没打字时不会想发送，打字时也不会想录音。轮流用，每个都能做得够大。
struct ChatInputBar: View {

    @Environment(AuthStore.self) private var auth

    /// 三个零件统一的高度。
    ///
    /// 和顶栏返回键同尺寸（40）。放成常量而不是三处各写一个数 ——
    /// 写三处的话，改一个忘一个，出来的东西就不一般齐了。
    static let controlHeight: CGFloat = 40

    /// 输入框的焦点。**由聊天页持有** ——
    /// 因为"点聊天区收键盘"要由它来关掉，藏在里面外面够不着。
    var focused: FocusState<Bool>.Binding

    @Binding var text: String

    /// 输入框里光标/选中的位置。
    ///
    /// 有了它，「复制」才知道用户是选中了一部分、还是什么都没选。
    /// **没选中的时候就复制整个输入框** —— 这是用户明确要的行为，
    /// 也是更符合直觉的：按了复制却什么都不发生，最让人困惑。
    @Binding var selection: TextSelection?

    var toolsOpen: Bool
    var onToggleTools: () -> Void
    var onPolish: () -> Void
    /// 录完一段语音（数据 + 时长）
    var onSendVoice: (Data, Double) -> Void
    /// 录音失败时要说的话（没给权限之类）
    var onVoiceProblem: (String) -> Void
    var onSend: () -> Void


    /// 是不是在"语音模式"。
    ///
    /// 【为什么改成模式切换，而不是一个常驻的麦克风按钮】
    ///
    /// 原来右边那个圆钮要"按住"才能录 —— 但它看起来就是个图标，
    /// 没人知道要按住。用户第一反应是**点一下**，然后觉得"没反应"。
    ///
    /// 模式切换解决了这个：点一下，整个输入框**变成**「按住 说话」——
    /// 这一步本身就是在告诉用户"接下来要按住"。
    /// 微信也是这么做的，用户不用学。
    @State private var voiceMode = DevFlags.voiceMode

    @State private var recorder = VoiceRecorder()
    /// 手指是不是已经上滑到"取消"区域了
    @State private var cancelling = false

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
        HStack(alignment: .bottom, spacing: 8) {
            circleButton(icon: toolsOpen ? "xmark" : "paperclip",
                         label: toolsOpen ? "收起工具栏" : "附件",
                         rotated: toolsOpen,
                         action: onToggleTools)

            inputArea

            // 一个位置，三个身份：
            //   语音模式 → 键盘（点它切回打字）
            //   有字     → 发送
            //   其他     → 麦克风（点它进语音模式）
            ZStack {
                if voiceMode {
                    circleButton(icon: "keyboard",
                                 label: "切换到打字",
                                 action: switchToText)
                        .transition(.scale.combined(with: .opacity))
                } else if canSend {
                    circleButton(icon: "arrow.up",
                                 label: "发送",
                                 filled: true,
                                 action: onSend)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    circleButton(icon: "mic.fill",
                                 label: "切换到语音",
                                 action: switchToVoice)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: canSend)
            .animation(.snappy(duration: 0.22), value: voiceMode)
        }
        .padding(7)
        // ── 输入栏**没有自己的背景** ──
        //
        // 之前这里铺过两层：先是 .card(.elevated)（不透明白卡片），
        // 后来换成 .regularMaterial（毛玻璃）—— 两次都是"一整块"，
        // 用户两次都说"不要单独弄出来一块"。
        //
        // 所以现在什么都不铺：三个零件（回形针 / 输入框 / 麦克风）
        // **各自有自己的底**，直接浮在聊天背景上。
        //
        // 顺带一个好处：整条栏不再需要在视觉上和背景"对齐颜色"——
        // 它压根不参与颜色。之前两次改都是在跟"这块圆角矩形的颜色
        // 跟背景差一点点"较劲，去掉就一了百了。
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        // 这里原来铺了一层 Theme.background 盖住屏幕最底
        //（为了盖住标签栏残留的白底）。现在**什么都不铺** ——
        //
        // 用户要的是「底部没有任何东西」：消息要能一直滚到屏幕最下沿，
        // 和顶上滚到状态栏底下一样。铺了东西就一定挡住消息。
        //
        // 标签栏那块白底是另一个问题（根子在 TabView 而不是输入栏），
        // 正确做法是让整页画布铺满，不是在输入栏上贴一块补丁。

        // ── 录音中的提示 ──
        //
        // ⚠️ **必须浮在输入栏上方**，不能就地显示在按钮上。
        //    因为用户的手指正好按着那个按钮 —— 提示放在那儿等于没放。
        //    微信也是把它放在上面一大块。
        //
        // 这一块我第一版**漏做了**：手势接好了，但屏幕上什么都不变，
        // 用户按住之后唯一的感受就是"点了没反应"。
        // **没有反馈的功能等于坏了的功能。**
        }
        .animation(.snappy(duration: 0.18), value: recorder.showsRecordingUI)
        .animation(.snappy(duration: 0.18), value: cancelling)
        // ── 录音提示浮在上方 ──
        //
        // ⚠️ **必须用 overlay，不能当 ZStack 的子视图。**
        //
        // 当子视图时，它一出现就改变了整个输入栏的布局尺寸，
        // 而输入栏上挂着 .glassEffect —— **液态玻璃必须重新渲染**。
        // 真机上重绘一次要一两秒，表现就是"代码说 318ms 就开始录了，
        // 但提示条一两秒后才弹出来"（用户的原话）。
        //
        // overlay 不参与父视图的尺寸计算，所以它出现/消失都**不会触发布局变化**，
        // 也就不会逼玻璃重绘。
        .overlay(alignment: .top) {
            if recorder.showsRecordingUI {
                recordingHint
                    // 偏移量要大于提示条自身高度，否则会压住输入栏
                    .offset(y: -160)
                    .transition(.opacity)
                    .allowsHitTesting(false)   // 别挡住手指
            }
        }
    }

    /// 录音时浮在上方的提示条。
    private var recordingHint: some View {
        VStack(spacing: 10) {
            Image(systemName: cancelling ? "xmark.circle.fill" : "waveform")
                .font(.system(size: 26))
                .foregroundStyle(cancelling ? Theme.danger : .white)
                // 这里原来有个 .symbolEffect(.variableColor.iterative) ——
                // 一个**一直在跑**的动画。它和玻璃重绘叠在一起，
                // 是"提示条弹不出来"的帮凶。静态图标信息量已经够了。

            Text(cancelling ? "松开手指，取消发送" : "松开发送")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(cancelling ? Theme.danger : .white)

            Text(String(format: "%.1f″", recorder.displaySeconds))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()

            // 快到上限时提醒一下，别让用户录到一半被截断还不知道
            if recorder.displaySeconds >= VoiceRecorder.maximumSeconds - 10 {
                Text("最长 \(Int(VoiceRecorder.maximumSeconds)) 秒")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(
            // 取消状态换成红底：**颜色是最快的反馈**，
            // 用户不用读字就知道"现在松手会取消"
            (cancelling ? Theme.danger.opacity(0.92) : Color.black.opacity(0.78)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    // MARK: - 中间的胶囊

    // MARK: - 中间的输入区

    @ViewBuilder
    private var inputArea: some View {
        if voiceMode {
            voiceHoldArea
        } else {
            inputPill
        }
    }

    /// 语音模式的"按住说话"。
    ///
    /// ⚠️ **不能包在 Button 里** —— Button 自带点击手势，
    /// 会把 DragGesture 吃掉，表现就是"按下去完全没反应"。
    /// 这个坑已经踩过一次（右边那个麦克风圆钮）。
    private var voiceHoldArea: some View {
        HStack(spacing: 8) {
            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(recorder.isRecording ? Theme.accent : Theme.textSecondary)

            Text(recorder.isRecording ? "正在录音…" : "按住 说话")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(recorder.isRecording ? Theme.accent : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.controlHeight)
        .pillGlass()
        .contentShape(Capsule())
        // ⚠️ **highPriorityGesture，不是 gesture。**
        //
        // 用户的实测把原因指得很清楚：
        //   「从按钮上滑或任何方向滑 → 秒开；单独按住不动 → 很慢」
        //
        // 滑动秒开、静止就慢，说明**有另一个手势在跟我抢**：
        // 一动就分出胜负（对方因为移动而失败，我立刻拿到），
        // 不动就得等系统判定（等到它确认这既不是点击也不是长按）。
        //
        // 那个"对方"是 .glassEffect —— 液态玻璃自带了按压识别。
        // highPriorityGesture 让我的手势优先，不再等它。
        //
        // 依然用 DragGesture(minimumDistance: 0) 而不是长按手势：
        // 它一次性给了按下、拖动、松手三件事，上滑取消需要拖动量；
        // 长按手势拿不到手指位置。
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // ⚠️ begin() 是**同步**的，会当场把"已经在录了"置上。
                    //    如果这里写成 `if !recorder.isRecording { Task { await start() } }`，
                    //    从建 Task 到 start 真正跑起来之间的那几次 onChanged
                    //    会各自再启动一次录音，几次会话激活互相排队 ——
                    //    实测就是一两秒的延迟。
                    if recorder.claimStart() {
                        AppLog.info(.data, "语音：手指按下")
                        // ⚠️ **所有界面可见的状态改动都在这个 Task 里做。**
                        //
                        // 直接在手势的 onChanged 里改，SwiftUI 会把手势期间的
                        // 变化推迟到手势结束 —— 按住不动时就是"要等松手才弹提示"。
                        // 跳一个 tick 就出了手势事务，会立刻渲染。
                        //
                        // 占位（claimStart）仍然是同步的，所以并发依然被挡住。
                        Task { @MainActor in
                            recorder.markRecordingUI()
                            if await recorder.startCaptureAndReport() == false {
                                onVoiceProblem("没有麦克风权限。去「设置 → 隐私与安全性 → 麦克风」里打开。")
                            }
                        }
                    }
                    cancelling = value.translation.height < -60
                }
                .onEnded { _ in
                    guard recorder.isRecording else { return }
                    if cancelling {
                        recorder.cancel()
                    } else if let result = recorder.finish() {
                        onSendVoice(result.data, result.seconds)
                    } else {
                        // 太短：多半是误触。但**不能默默什么都不做** ——
                        // 用户分不清"误触被丢掉了"和"功能坏了"。
                        Haptics.warning()
                        onVoiceProblem("说话时间太短了，按住多说一会儿再松手。")
                    }
                    cancelling = false
                }
        )
    }

    private func switchToVoice() {
        Haptics.tap()
        focused.wrappedValue = false   // 先收键盘，不然切换时会顶一下
        withAnimation(.snappy(duration: 0.24)) { voiceMode = true }

        // 进语音模式就**预热音频会话** ——
        // 这样等用户按下按钮时，只剩一句 record()，是立刻开始的。
        // 不预热的话，按下之后要等一两百毫秒才开始采集，
        // 用户说的头两个字会被吃掉（用户报的"按下之后有延迟"就是这个）。
        //
        // 代价：会话开着的时候状态栏有麦克风小圆点。这是系统行为，
        // 关不掉 —— 除非不预热（那就回到有延迟）。所以只在语音模式里热。
        Task {
            if await recorder.warmUp() == false {
                onVoiceProblem("没有麦克风权限。去「设置 → 隐私与安全性 → 麦克风」里打开。")
            }
        }
    }

    private func switchToText() {
        Haptics.tap()
        withAnimation(.snappy(duration: 0.24)) { voiceMode = false }
        // 离开语音模式就把麦克风还回去（状态栏那个小圆点也就灭了）
        recorder.coolDown()
        // 切回打字时把光标放回去 —— 用户切回来就是要打字的
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused.wrappedValue = true }
    }

    private var inputPill: some View {
        HStack(spacing: 8) {
            // 头像：纯粹是"这是你在说话"的锚点
            if let account = auth.account {
                Avatar(initial: String(account.displayName.prefix(1)).uppercased(),
                       seed: account.avatarSeed,
                       size: 26,
                       url: account.avatarURL)
            }

            TextField("说点什么…", text: $text, selection: $selection, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...5)
                .focused(focused)

            // Telegram 这个位置是表情。我们放 AI 改写 ——
            // 同一个视觉位置，但按下去真的有事发生
            //（放一个点了没反应的表情按钮，比空着还糟）。
            if canSend {
                Button(action: onPolish) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI 改写这句话")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.18), value: canSend)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        // 和两边圆钮**一模一样的高度**，三个零件才一般齐
        .frame(height: Self.controlHeight)
        .pillGlass()
        // **输入框也不加底。**
        //
        // 这是最后一块 —— 前面拆了四次都留着它，所以屏幕中间
        // 一直有一条 #F7F8FA（画布是 #F2F3F5），用户看到的就是"还有一层画布"。
        //
        // 没有底之后靠 placeholder 文字和那个小头像说明"这里能打字"，
        // 和消息气泡共用同一张画布 —— 也就是用户要的"全都用那个画布"。
    }

    // MARK: - 圆形按钮

    /// 圆按钮的**外观**，不含 Button。
    ///
    /// ⚠️ 拆出来是必须的 —— 麦克风**不能用 Button**。
    ///
    /// `Button` 自带一个点击手势，会把挂在它上面的 `DragGesture` 吃掉：
    /// 表现是**按下去完全没反应**（没有权限弹窗、没有提示、什么都没有）。
    /// 我第一版就是把 DragGesture 挂在了 Button 上，收到的反馈是"没反应"。
    ///
    /// 所以：能点的用 `circleButton`，要按住/拖动的用这个 + 自己挂手势。
    private func circleLabel(icon: String,
                             filled: Bool = false,
                             active: Bool = false,
                             rotated: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(filled ? .white : (active ? Theme.accent : Theme.textSecondary))
            // 尺寸统一 40×40，和顶栏返回键一样。
            // 写常量不写三遍数字 —— 改一个忘一个就不齐了。
            .frame(width: Self.controlHeight, height: Self.controlHeight)
            // 真玻璃，挂在**外观**上而不是 buttonStyle 上。
            //
            // ⚠️ 之前用 .buttonStyle(.glass)：那个样式会**自己再包一圈内边距**，
            // 于是设了 40 磅、看起来却有 50 磅，比中间的输入框大一圈
            //（用户：「两边这两个有点大」）。
            //
            // 换成 .glassEffect 之后，尺寸就是我写的那个数，三个零件才真齐。
            .glassEffect(filled ? .regular : .regular.interactive(), in: .circle)
            .rotationEffect(.degrees(rotated ? 90 : 0))
    }

    private func circleButton(icon: String,
                              label: String,
                              filled: Bool = false,
                              active: Bool = false,
                              rotated: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            circleLabel(icon: icon, filled: filled, active: active, rotated: rotated)
        }
        // 玻璃已经在外观那一层了（见 circleLabel），这里只要 plain。
        // 用 .buttonStyle(.glass) 会**多包一圈内边距**，圆钮就比输入框大一圈。
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension TextSelection {
    /// 从这段文字里取出**被选中的那部分**。
    ///
    /// 没有选中（只是光标停着）时返回 nil —— 调用方据此决定
    /// "那就复制全部"。
    func selectedText(in text: String) -> String? {
        // ⚠️ `indices` 是个**枚举**，而且两个分支给的东西不一样：
        //     .selection      → 单个 Range（普通的拖选）
        //     .multiSelection → RangeSet（多光标那种，能有好几段）
        //
        // 我第一版把两者当成同一种、直接写 `.ranges`，
        // 编译报错 "cannot assign value of type 'Range<String.Index>'
        // to type 'RangeSet<String.Index>'" —— 这才看明白它们不同。
        switch indices {
        case .selection(let range):
            let picked = String(text[range])
            return picked.isEmpty ? nil : picked

        case .multiSelection(let set):
            let picked = set.ranges.map { String(text[$0]) }.joined()
            return picked.isEmpty ? nil : picked

        @unknown default:
            return nil
        }
    }

}


// ─────────────────────────────────────────────────────────────
// 关于"为什么输入栏所有零件都没有底色"
//
// 来回改了四次，把结论写在这里，免得以后再走一遍：
//
//   第一次：一整块不透明白卡片（.card(.elevated)）—— 用户："不要单独弄出来一块"
//   第二次：换成毛玻璃材质（.regularMaterial）—— 还是"一块"，只是能透过去
//   第三次：去掉整块，但每个零件留着自己的小底
//   第四次：**小底也全去掉** —— 用户："全都用中央信息气泡下面的那个画布"
//
// 折腾四次的原因是：我一直把"透明"理解成
// "**能透出后面的颜色**"（半透明 / 毛玻璃），
// 而用户要的是"**根本就没有这一层**"。
//
// 这两个是完全不同的东西：
//   半透明 = 我铺了一层，只是它不挡光   → 颜色永远和背景差一点点
//   没有   = 我不参与颜色               → 不可能有色差
//
// 验证方法（这次就是这么找到的）：截图转 BMP，
// 逐行取像素量颜色。BMP 没有 PNG 的滤波，读到的是真值。
// 结果是：屏幕左右边缘从头到尾都是画布色 #F2F3F5，
// 只有正中间那条 #F7F8FA —— 那不是"一条带"，是输入框胶囊自己。
// **量一下比猜十次都快。**
// ─────────────────────────────────────────────────────────────


private extension View {
    /// 给"长条"零件套上一层尽量接近液态玻璃的底。
    ///
    /// 圆钮那边直接 `.buttonStyle(.glass)` 就够了（它们本来就是 Button）。
    /// 输入框不是按钮，用不了那个按钮样式，所以退一步用系统材质 + 细描边。
    ///
    /// **不要自己调颜色去"模仿"系统那套。** 这一轮已经在
    /// "自己调一个看起来差不多的底"上面栽了四次 —— 能用系统的就用系统的，
    /// 用不了的就用系统材质，别手配色值。
    @ViewBuilder
    func pillGlass() -> some View {
        // 真玻璃。
        //
        // API 在 **SwiftUICore** 里，不在 SwiftUI 里 —— 我第一次只搜了
        // SwiftUI，只找到 .buttonStyle(.glass)（那是给按钮的），
        // 于是以为"非按钮的容器没有玻璃 API"，退而用了材质。
        // 结果用户一眼就看出来："中间的输入栏没有特效"。
        //
        // 教训：搜 API 要把相关的框架都搜一遍。
        // SwiftUICore 是所有视图修饰符真正住的地方。
        self.glassEffect(.regular, in: .capsule)
    }
}
