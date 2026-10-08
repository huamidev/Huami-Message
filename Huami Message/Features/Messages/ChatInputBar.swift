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
        // ── 用**和整页画布一模一样的颜色**铺到屏幕最底 ──
        //
        // 为什么需要它：聊天页是压栈进 TabView 的，标签栏虽然被藏了，
        // **它占的那块区域还在**，而且系统会给它画一层底（白色）。
        // 不盖的话，屏幕最下面会露出一条和画布不一样的色带。
        //
        // 为什么要 .ignoresSafeAreaEdges: .bottom 而不是 .ignoresSafeArea()：
        // 后者在这个位置不生效（试过，用红色探针量出来底边停在安全区边界）。
        //
        // ⚠️ 关键：这个背景**只挂在输入栏这一层**，
        //    不要挂到外面那个装着"渐隐 + 回到最新"的 VStack 上 ——
        //    我上一版就是挂在外面，于是整片区域变成不透明，
        //    把消息挡住了（用户报的"遮挡信息"就是这个）。
        //
        //    颜色必须**等于** Theme.background：等于就没边，
        //    不等于就一定看得出一条色带（这一点已经来回折腾过三次）。
        .background(Theme.background, ignoresSafeAreaEdges: .bottom)

        // ── 录音中的提示 ──
        //
        // ⚠️ **必须浮在输入栏上方**，不能就地显示在按钮上。
        //    因为用户的手指正好按着那个按钮 —— 提示放在那儿等于没放。
        //    微信也是把它放在上面一大块。
        //
        // 这一块我第一版**漏做了**：手势接好了，但屏幕上什么都不变，
        // 用户按住之后唯一的感受就是"点了没反应"。
        // **没有反馈的功能等于坏了的功能。**
        if recorder.showsRecordingUI {
            recordingHint
                // ⚠️ 这个偏移量要**大于提示条自己的高度**，
                //    否则它会压住输入栏（我第一版写 -118，正好压住一条边）。
                //    提示条大概 140 磅高，留 20 磅空隙 → 160。
                .offset(y: -160)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(1)
        }
        }
        .animation(.snappy(duration: 0.18), value: recorder.showsRecordingUI)
        .animation(.snappy(duration: 0.18), value: cancelling)
    }

    /// 录音时浮在上方的提示条。
    private var recordingHint: some View {
        VStack(spacing: 10) {
            Image(systemName: cancelling ? "xmark.circle.fill" : "waveform")
                .font(.system(size: 26))
                .foregroundStyle(cancelling ? Theme.danger : .white)
                .symbolEffect(.variableColor.iterative, isActive: !cancelling)

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
        // **不加底** —— 用整页那个画布（见文件末尾的说明）
        .contentShape(Capsule())
        .gesture(
            // DragGesture(minimumDistance: 0) 而不是长按手势：
            // 它一次性给了按下、拖动、松手三件事，
            // 而"上滑取消"正好需要一个拖动量。
            // 长按手势只能告诉你按够了没有，拿不到手指位置。
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !recorder.isRecording {
                        AppLog.info(.data, "语音：手指按下")
                        Task {
                            if await recorder.start() == false {
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
        focused.wrappedValue = false          // 先收键盘，不然切换时会顶一下
        withAnimation(.snappy(duration: 0.24)) { voiceMode = true }
    }

    private func switchToText() {
        Haptics.tap()
        withAnimation(.snappy(duration: 0.24)) { voiceMode = false }
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
            .frame(width: 34, height: 34)
            // 只有"发送"那个按钮保留实心底 —— 它是个**动作按钮**，
            // 不是输入区，需要一眼认出"点这里发出去"。
            // 其余（回形针 / 麦克风）不加底，直接浮在画布上。
            .background {
                if filled {
                    Circle().fill(Theme.myBubbleGradient)
                }
            }
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
