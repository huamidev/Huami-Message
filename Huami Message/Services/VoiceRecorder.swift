import AVFoundation
import Observation

/// 录音。
///
/// 【为什么按住才录、松开就停】
///
/// 语音消息是**一次说完一件事**，不是录播客。
/// 按住录、松开停，用户对"什么时候在录"有完全的掌控 ——
/// 点一下开始、再点一下停的那种，人总会忘记自己还在录。
///
/// 微信那套（松手发送、上滑取消）已经成了肌肉记忆，照做最省学习成本。
@MainActor
@Observable
final class VoiceRecorder {

    private(set) var isRecording = false

    /// 界面上该不该显示"正在录"。
    /// 多出来的那半句只是给开发自检用的 —— 截图按不住按钮。
    var showsRecordingUI: Bool { isRecording || DevFlags.fakeRecording }

    /// 界面上显示的秒数
    var displaySeconds: Double {
        isRecording ? seconds : (DevFlags.fakeRecording ? 3.4 : 0)
    }

    /// 已经录了多少秒（界面上要跳数字）
    private(set) var seconds: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    /// 最短时长。
    ///
    /// 0.5 秒以下的多半是**误触** —— 用户只是碰了一下按钮。
    /// 发出去是一段"嗯"的杂音，对方还得点开听，两边都烦。
    static let minimumSeconds: Double = 0.8

    /// 最长时长。够说一件事了，也挡住"录着忘了"把存储撑爆。
    static let maximumSeconds: Double = 60

    /// 音频会话是不是已经热着了。
    private var isWarm = false

    /// **预热**：进语音模式时调一次。
    ///
    /// 【为什么必须提前做 —— 这是"按住之后有延迟"的真正原因】
    ///
    /// 激活 AVAudioSession 要一两百毫秒，是整条链路里最慢的一步。
    /// 原来它在按下按钮之后才做 —— 界面提示虽然立刻就亮了，
    /// **但真正开始采集声音要等它做完**，用户说的头两个字就被吃掉了。
    ///
    /// 提前打开之后，按下时只剩一句 recorder.record()，是立刻开始的。
    ///
    /// 代价要说清楚：会话开着的时候，系统状态栏会显示**麦克风小圆点**。
    /// 也就是说"停在语音模式"的那段时间里，小圆点是亮着的。
    /// 这是系统行为，关不掉 —— 除非不预热（那就回到有延迟）。
    /// 所以我们只在**语音模式**里预热，切回打字就立刻冷掉。
    func warmUp() async -> Bool {
        if isWarm { return true }

        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            AppLog.error(.network, "麦克风权限没拿到")
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            isWarm = true
            return true
        } catch {
            AppLog.error(.network, "音频会话预热失败：\(error.localizedDescription)")
            return false
        }
    }

    /// **冷掉**：离开语音模式时调一次，把麦克风还回去（小圆点也就灭了）。
    func coolDown() {
        guard !isRecording else { return }   // 正在录就别动
        guard isWarm else { return }
        isWarm = false
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    /// 开始录。返回 false 表示没拿到权限。
    ///
    /// 【为什么把界面反馈放在最前面 —— 一个真实的卡顿】
    ///
    /// 原来是"权限 → 音频会话 → 录音器 → 全部成功后才置 isRecording"。
    /// 而**激活音频会话本身就要一两百毫秒**，用户按住之后
    /// 先卡一下才看到提示条（用户报的"按住好像会卡一下，不是很及时"）。
    ///
    /// 现在改成：**先把"正在录"点亮**（同步、立刻），
    /// 再去准备真正的录音。准备失败就把界面收回去并报错。
    ///
    /// 代价是"正在录"可能短暂地是个乐观状态 —— 但人耳听到的是
    /// 按键的即时反馈，而几十毫秒的空档没人听得出来。
    func start() async -> Bool {
        guard !isRecording else { return true }

        // ① 同步点亮界面 —— 一个 await 都不要有
        isRecording = true
        seconds = 0
        Haptics.tap()
        startTimer()

        // ② 再去准备真正的录音
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            AppLog.error(.network, "麦克风权限没拿到")
            stopQuietly()          // 把乐观状态收回去，不能停在假的"正在录"
            return false
        }

        // 会话已经热着就直接跳过 —— 这是"按下即录"的关键。
        // 没热（比如用户从别处直接进来）才现场开，慢一点但能work。
        if !isWarm {
            do {
                // .playAndRecord + .defaultToSpeaker：录完能立刻外放，
                // 不用切来切去（只录不放的话，放音会走听筒，声音小得听不见）
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                isWarm = true
            } catch {
                AppLog.error(.network, "录音会话起不来：\(error.localizedDescription)")
                stopQuietly()
                return false
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        fileURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050,          // 人声够用，文件小一半
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
        } catch {
            AppLog.error(.network, "录音起不来：\(error.localizedDescription)")
            stopQuietly()
            return false
        }

        return true
    }

    /// 计时器。
    ///
    /// ⚠️ **必须用 RunLoop.main.add(_, forMode: .common)。**
    ///
    /// 原来用的是 `Timer.scheduledTimer` —— 它加在 **default 模式**上。
    /// 而**手指按住屏幕的时候，主 runloop 处于 tracking 模式**，
    /// default 模式下的计时器根本不会触发：提示条上的秒数就停在那儿不动
    ///（这是"按住会卡一下"的第二个原因，也是最像"卡住"的那个）。
    ///
    /// .common 模式包含 tracking，所以按住期间照常走。
    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.seconds += 0.1
                // 到上限自动停 —— 不能让用户一直录下去
                if self.seconds >= Self.maximumSeconds { _ = self.finish() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 把乐观点亮的界面收回去（准备失败时用），不发声。
    private func stopQuietly() {
        recorder?.stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        cleanup()
    }

    /// 结束并返回（音频数据, 时长）。太短或没录成返回 nil。
    @discardableResult
    func finish() -> (data: Data, seconds: Double)? {
        guard isRecording, let recorder, let fileURL else { return nil }

        let duration = max(recorder.currentTime, seconds)
        recorder.stop()
        cleanup()

        guard duration >= Self.minimumSeconds else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)

        Haptics.success()
        return (data, min(duration, Self.maximumSeconds))
    }

    /// 取消（上滑松手）：**什么都不留**。
    func cancel() {
        guard isRecording else { return }
        recorder?.stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        cleanup()
        Haptics.warning()
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        fileURL = nil
        isRecording = false
        seconds = 0
        // ⚠️ 这里**不**关会话。
        //
        // 关掉的话，用户松开手指、再按下一次，又得重新等那一两百毫秒 ——
        // 连续发几条语音的时候每一条都卡。会话由 coolDown() 负责关，
        // 那个只在**离开语音模式**时调。
    }
}
