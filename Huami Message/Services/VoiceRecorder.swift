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

    /// 手指按下的时刻。纯粹为了量延迟 —— 这一块来回改了四次，
    /// 全都是靠猜。日志打出来，一次就能知道慢在哪一段。
    private var pressedAt: Date?

    /// "已经有人开始准备了" —— **同步**置位，用来挡住并发的重复启动。
    private var isPreparing = false

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
        AppLog.info(.data, "语音耗时：权限 \(elapsed())")
        guard allowed else {
            AppLog.error(.network, "麦克风权限没拿到")
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try await Self.activateOffMainThread(session)
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
        let session = AVAudioSession.sharedInstance()
        // coolDown 是同步函数（界面切模式时直接调），所以这里起个 Task 就返回。
        // 关会话慢一点没关系 —— 没有任何人等在它后面。
        Task.detached(priority: .utility) {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
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
    /// 一步到位的老入口（内部用）。界面走的是 claimStart + markRecordingUI 两步，
    /// 因为界面那一步必须跳出手势事务。
    func start() async -> Bool {
        guard claimStart() else { return true }
        markRecordingUI()
        return await beginCapture()
    }

    /// **同步**的那一半：占位 + 点亮界面。返回 false 表示"已经在录了，别再来一次"。
    ///
    /// 【为什么必须拆出来 —— 1-2 秒延迟的真正原因】
    ///
    /// 原来调用方是这么写的：
    ///
    ///     if !recorder.isRecording {
    ///         Task { await recorder.start() }      // start 是 async
    ///     }
    ///
    /// 而 isRecording 是在 **start() 内部**才置上的。
    /// 从 Task 创建到 start() 真正跑起来之间有**一次调度跳转**，
    /// 这期间手指的 onChanged 会连续触发好几次 ——
    /// **好几个 start() 同时进去，每个都去激活一次音频会话**，
    /// 它们互相排队，实测下来就是一两秒（用户报的"按下 1-2s 才开始录"）。
    ///
    /// 拆开之后，"已经在录了"这个判断是**同步**做的，
    /// 第二次 onChanged 根本进不来。异步的部分只做一次。
    /// 第一步：**同步**占位。只挡并发，**不碰任何界面可见的状态**。
    ///
    /// 【为什么必须和下一步分开 —— "按住不动很慢、一滑就秒开"的真正原因】
    ///
    /// 用户的实测：
    ///   从按钮上滑或任何方向滑 → **秒开**
    ///   单独按住不动           → **很慢**
    ///
    /// 滑动会**连续触发很多次** onChanged，中途总有渲染机会；
    /// 而按住不动时 onChanged **只在按下那一瞬间触发一次**，
    /// 而 SwiftUI 会把**手势进行中**的状态变化推迟到手势结束才渲染 ——
    /// 所以提示条要等到松手才画出来，看起来就是"很慢"。
    ///
    /// 所以：这里只做同步占位（挡住并发），界面状态交给
    /// markRecordingUI()，由调用方**扔到下一个 tick**去改 ——
    /// 那一步已经跳出了手势事务，SwiftUI 会立刻渲染。
    func claimStart() -> Bool {
        guard !isRecording, !isPreparing else { return false }
        isPreparing = true
        pressedAt = Date()
        return true
    }

    /// 第二步：把"正在录"显示出来。**必须由调用方在 Task/下一个 tick 里调用。**
    func markRecordingUI() {
        isRecording = true
        seconds = 0
        Haptics.tap()
        startTimer()
    }

    /// 在**主线程之外**激活音频会话。
    ///
    /// 【为什么必须这样 —— 系统自己说出来的】
    ///
    /// 在手机上实测时，控制台里出现了这句：
    ///
    ///     AVAudioSession_iOS.mm:978  This method can lead to UI
    ///     unresponsiveness if called on the main thread. Consider using
    ///     the asynchronous activate/deactivate API instead...
    ///
    /// 也就是说：**setActive 在主线程上调用会把 UI 卡住**。
    /// 这正是"按住不动很慢、滑动才唤出提示"的真正原因 ——
    /// 主线程被阻塞，提示条根本画不出来（滑动时事件密集，
    /// 阻塞结束后总有一次重绘机会，所以看起来是"秒开"）。
    ///
    /// 而同一份日志里，**录音本身只用 64ms 就开始了** ——
    /// 慢的从来不是录音，是界面。
    ///
    /// 这个 SDK 版本里没找到 async 版的 activate（它是 Objective-C API，
    /// 异步版在生成的 overlay 里，这里是纯 Swift 环境），
    /// 所以用 detached task 把它挪出主线程 —— 效果一样，而且不挑版本。
    private static func activateOffMainThread(_ session: AVAudioSession) async throws {
        try await Task.detached(priority: .userInitiated) {
            try session.setActive(true)
        }.value
    }

    private static func deactivateOffMainThread(_ session: AVAudioSession) async {
        await Task.detached(priority: .utility) {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }.value
    }

    /// 从"手指按下"到现在过了多久。日志用。
    ///
    /// ⚠️ 写成**类的方法**而不是某个函数里的局部函数 ——
    /// 我第一次写成了局部函数，结果被插进了 warmUp 的作用域，
    /// 在 beginCapture 里就"找不到 elapsed"，编译不过。
    /// 墙上时钟的毫秒时间戳。
    ///
    /// 用来和系统日志（比如 "Gesture: System gesture gate timed out."）
    /// 对齐时间轴 —— 我们自己打的日志没有时间，只能看出顺序，
    /// 看不出"到底隔了多久"。而这一次要查的恰恰就是**间隔**。
    static func stamp() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }

    private func elapsed() -> String {
        guard let pressedAt else { return "?" }
        return String(format: "%.0fms", Date().timeIntervalSince(pressedAt) * 1000)
    }

    /// 给界面用的入口：从"已经 begin 过"的状态继续把录音准备起来。
    func startCaptureAndReport() async -> Bool {
        await beginCapture()
    }

    /// **异步**的那一半：权限 + 会话 + 录音器。
    private func beginCapture() async -> Bool {
        defer { isPreparing = false }

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
                try await Self.activateOffMainThread(session)
                isWarm = true
                AppLog.info(.data, "语音耗时：会话 \(elapsed())")
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
            // 录音器的创建和启动也放到主线程之外 —— 它同样要碰音频硬件。
            // 会话已经热着的情况下，这里就是最后一段可能卡主线程的代码。
            let built = try await Task.detached(priority: .userInitiated) {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                recorder.record()
                return recorder
            }.value
            self.recorder = built
            AppLog.info(.data, "语音耗时：**真正开始录 \(elapsed())**  @\(Self.stamp())")
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

        // 录到的字节数 —— 空录音（比如麦克风没真的打开）一眼就能看出来：
        // 22kHz 单声道录 2 秒大约 6~8 KB，只有几百字节就说明什么都没录到。
        AppLog.info(.data, "语音录制：\(data.count) 字节 / \(String(format: "%.1f", duration)) 秒")

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
        // 注意：**不复位 isPreparing** —— 它是 beginCapture 用 defer 管的，
        // 在这里复位会把"还在准备中"这个信息抹掉，并发就又漏进来了。
        seconds = 0
        // ⚠️ 这里**不**关会话。
        //
        // 关掉的话，用户松开手指、再按下一次，又得重新等那一两百毫秒 ——
        // 连续发几条语音的时候每一条都卡。会话由 coolDown() 负责关，
        // 那个只在**离开语音模式**时调。
    }
}
