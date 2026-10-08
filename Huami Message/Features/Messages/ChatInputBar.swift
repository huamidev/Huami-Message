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

    @FocusState private var isFocused: Bool

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

            inputPill

            // 一个位置，两个身份
            ZStack {
                if canSend {
                    circleButton(icon: "arrow.up",
                                 label: "发送",
                                 filled: true,
                                 action: onSend)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // ⚠️ 麦克风**不是普通按钮** —— 它要"按住"。
                    //
                    // 用 DragGesture(minimumDistance: 0) 而不是长按手势：
                    // 它一次性给了按下、拖动、松手三件事，
                    // 而"上滑取消"正好需要一个拖动量。
                    // 长按手势只能告诉你按够了没有，拿不到手指位置。
                    circleLabel(icon: recorder.isRecording ? "waveform" : "mic.fill",
                                active: recorder.isRecording)
                        // contentShape：让整个圆都能按到，而不只是那根图标线条
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // 这几行日志是**排查用的** ——
                                    // "按下去没反应"可能是三层：手势没触发、
                                    // 权限没拿到、录音器没起来。不打日志只能猜。
                                    if !recorder.isRecording {
                                        AppLog.info(.data, "麦克风：手指按下")
                                        Task {
                                            if await recorder.start() == false {
                                                AppLog.error(.network, "麦克风：启动失败（多半是权限）")
                                                onVoiceProblem("没有麦克风权限。去「设置 → 隐私与安全性 → 麦克风」里打开。")
                                            } else {
                                                AppLog.info(.data, "麦克风：开始录音")
                                            }
                                        }
                                    }
                                    cancelling = value.translation.height < -60
                                }
                                .onEnded { _ in
                                    AppLog.info(.data, "麦克风：手指松开（正在录=\(recorder.isRecording)）")
                                    guard recorder.isRecording else { return }
                                    if cancelling {
                                        recorder.cancel()
                                    } else if let result = recorder.finish() {
                                        onSendVoice(result.data, result.seconds)
                                    } else {
                                        // 太短：多半是误触，不发。
                                        //
                                        // 但**不能默默什么都不做** ——
                                        // 用户分不清"误触被丢掉了"和"功能坏了"。
                                        // 我第一版就是默默丢掉，结果收到的反馈是
                                        // "点击无反应"。
                                        Haptics.warning()
                                        onVoiceProblem("说话时间太短了，按住多说一会儿再松手。")
                                    }
                                    cancelling = false
                                }
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.2), value: canSend)
        }
        .padding(7)
        .card(.elevated, radius: 26)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)

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
                .focused($isFocused)

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
        .background(Theme.surfaceAlt, in: Capsule())
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
            .background {
                if filled {
                    Circle().fill(Theme.myBubbleGradient)
                } else {
                    Circle().fill(Theme.surfaceAlt)
                        .overlay { Circle().strokeBorder(Theme.separator, lineWidth: 0.8) }
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
