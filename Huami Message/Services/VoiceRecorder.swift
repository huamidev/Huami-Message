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

    /// 开始录。返回 false 表示没拿到权限。
    func start() async -> Bool {
        guard !isRecording else { return true }

        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { return false }

        let session = AVAudioSession.sharedInstance()
        do {
            // .playAndRecord + .defaultToSpeaker：录完能立刻外放，
            // 不用切来切去（只录不放的话，放音会走听筒，声音小得听不见）
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            AppLog.error(.network, "录音会话起不来：\(error.localizedDescription)")
            return false
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
            return false
        }

        isRecording = true
        seconds = 0
        Haptics.tap()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.seconds += 0.1
                // 到上限自动停 —— 不能让用户一直录下去
                if self.seconds >= Self.maximumSeconds { _ = self.finish() }
            }
        }
        return true
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
