import AVFoundation
import Observation
import SwiftUI

/// 播放语音。全局只有一个 —— 同一时刻只该有一条语音在响。
///
/// 为什么不做成每条消息一个播放器：那样两条语音能同时播，
/// 听起来像故障。而且用户点第二条时，第一条必须停 —— 这是产品要求，
/// 不是技术细节。
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {

    static let shared = VoicePlayer()

    /// 正在播的那条（nil 表示没在播）
    private(set) var playingURL: URL?

    /// 正在加载（网络音频要下载一下）
    private(set) var loadingURL: URL?

    private var player: AVAudioPlayer?

    override private init() { super.init() }

    func isPlaying(_ url: URL) -> Bool { playingURL == url }
    func isLoading(_ url: URL) -> Bool { loadingURL == url }

    /// 点一下：正在播就停，否则播它。
    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        loadingURL = url

        Task {
            defer { loadingURL = nil }
            do {
                let data: Data
                if url.isFileURL {
                    data = try Data(contentsOf: url)
                } else {
                    let (loaded, _) = try await URLSession.shared.data(from: url)
                    data = loaded
                }

                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)

                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.prepareToPlay()
                player.play()
                self.player = player
                playingURL = url
            } catch {
                AppLog.error(.network, "语音播放失败：\(error.localizedDescription)")
                Haptics.warning()
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingURL = nil
        }
    }
}

/// 语音气泡：一个播放键 + 时长。
///
/// 【为什么不做波形图】
///
/// 波形好看，但它需要**把整段音频先解码出来算振幅** ——
/// 列表里十条语音就是十次解码，滚动会卡。
/// 微信也只有一条弧线，用户想知道的其实只有"多长"和"点哪里播"。
struct VoiceBubble: View {

    let url: URL
    let seconds: Double
    let isMine: Bool

    @State private var player = VoicePlayer.shared

    private var label: String {
        // 超过 60 秒的按"1′05″"显示，否则纯秒数
        let total = Int(seconds.rounded())
        if total >= 60 { return "\(total / 60)′\(String(format: "%02d", total % 60))″" }
        return "\(max(total, 1))″"
    }

    var body: some View {
        Button {
            Haptics.tap()
            player.toggle(url)
        } label: {
            HStack(spacing: 9) {
                if player.isLoading(url) {
                    ProgressView().controlSize(.small)
                        .tint(isMine ? .white : Theme.textSecondary)
                } else {
                    Image(systemName: player.isPlaying(url) ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isMine ? .white : Theme.accent)
                }

                // 一条弧线暗示"这是声音"，不是文字
                Capsule()
                    .fill(isMine ? Color.white.opacity(0.55) : Theme.textTertiary.opacity(0.4))
                    .frame(width: max(28, min(CGFloat(seconds) * 2.4, 120)), height: 3)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isMine ? .white : Theme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("语音消息，\(label)")
    }
}
