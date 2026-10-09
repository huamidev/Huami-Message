/// 录音 + 转成两边都能播的格式。
///
/// 【为什么要转格式 —— 这是跨平台语音的真问题】
///
/// iOS 版录的是 **m4a**（AVAudioRecorder 的默认）。
/// 浏览器里 MediaRecorder 录出来的是 **webm/opus**（Safari 上是 m4a）。
///
/// 问题在于：**iOS 播不了 webm**（AVPlayer 不支持 opus）。
/// 也就是说，安卓朋友发一条语音，iOS 用户点开是**没有声音**的 ——
/// 而这恰恰是我们做网页版的目的（让安卓朋友能用）。
///
/// 三种解法：
///   ① 服务器转码（Edge Function + ffmpeg）—— 重，而且 Deno 里没有 ffmpeg
///   ② 各播各的 —— 但那就等于"安卓发的语音 iOS 听不了"，不算解决
///   ③ **在浏览器里转成 WAV** ← 选这个
///
/// WAV 是无压缩的，**iOS、安卓、桌面浏览器都能直接播**。
/// 体积代价：16kHz 单声道大约每秒 32 KB —— 一条 10 秒的语音 320 KB，
/// 对语音消息完全可以接受（m4a 大概是它的十分之一，但换来的是"能播"）。
///
/// 转码全程在用户手机上做，不花服务器一分钱、不增加一次网络往返。

const TARGET_RATE = 16000   // 语音够用；再高只是白占体积

/// 开始录音，返回一个"停止"函数和拿结果的 Promise。
export function startRecording(): {
  stop: () => Promise<{ blob: Blob; seconds: number }>
  cancel: () => void
} {
  let recorder: MediaRecorder | null = null
  let stream: MediaStream | null = null
  let chunks: Blob[] = []
  let startedAt = Date.now()
  let cancelled = false

  const ready = navigator.mediaDevices.getUserMedia({ audio: true }).then((s) => {
    stream = s
    // 优先 mp4（Safari 支持），再退到 webm —— 反正后面都要转 WAV，
    // 这里只是挑一个浏览器真的能录的格式
    const type = ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm']
      .find((t) => MediaRecorder.isTypeSupported(t))
    recorder = new MediaRecorder(s, type ? { mimeType: type } : undefined)
    chunks = []
    recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data) }
    recorder.start()
    startedAt = Date.now()
    return recorder
  })

  function cleanup() {
    stream?.getTracks().forEach((t) => t.stop())
    stream = null
  }

  return {
    async stop() {
      const rec = recorder ?? (await ready)
      const seconds = (Date.now() - startedAt) / 1000

      const raw = await new Promise<Blob>((resolve) => {
        rec.onstop = () => resolve(new Blob(chunks, { type: rec.mimeType }))
        rec.stop()
      })
      cleanup()
      if (cancelled) throw new Error('cancelled')

      const wav = await toWav(raw)
      return { blob: wav, seconds }
    },
    cancel() {
      cancelled = true
      try { recorder?.stop() } catch { /* 还没开始录就取消了 */ }
      cleanup()
    },
  }
}

/// 把浏览器录出来的东西转成 16kHz 单声道 WAV。
///
/// 两步：
///   ① 用 WebAudio 解码（浏览器自己知道怎么解它录的格式）
///   ② 用 OfflineAudioContext 单声道重采样到 16k
///      —— 比自己写重采样可靠得多，而且浏览器会做抗混叠
async function toWav(source: Blob): Promise<Blob> {
  const arrayBuffer = await source.arrayBuffer()

  const decodeContext = new AudioContext()
  const decoded = await decodeContext.decodeAudioData(arrayBuffer)
  await decodeContext.close()

  const length = Math.max(1, Math.ceil(decoded.duration * TARGET_RATE))
  const offline = new OfflineAudioContext(1, length, TARGET_RATE)
  const node = offline.createBufferSource()
  node.buffer = decoded
  node.connect(offline.destination)
  node.start()

  const rendered = await offline.startRendering()
  const samples = rendered.getChannelData(0)
  return encodeWav(samples, TARGET_RATE)
}

/// 写一个标准的 16 位 PCM WAV。
///
/// 头部 44 字节，之后是交织的采样。格式老到不能再老，
/// 但正因为老，**什么都能播** —— 这就是选它的全部理由。
function encodeWav(samples: Float32Array, sampleRate: number): Blob {
  const buffer = new ArrayBuffer(44 + samples.length * 2)
  const view = new DataView(buffer)

  const writeText = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i))
  }

  writeText(0, 'RIFF')
  view.setUint32(4, 36 + samples.length * 2, true)
  writeText(8, 'WAVE')
  writeText(12, 'fmt ')
  view.setUint32(16, 16, true)        // fmt 块长度
  view.setUint16(20, 1, true)         // 1 = PCM
  view.setUint16(22, 1, true)         // 单声道
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * 2, true)   // 每秒字节数
  view.setUint16(32, 2, true)         // 每帧字节数
  view.setUint16(34, 16, true)        // 位深
  writeText(36, 'data')
  view.setUint32(40, samples.length * 2, true)

  let offset = 44
  for (let i = 0; i < samples.length; i++) {
    // 夹到 [-1, 1]：解码出来的浮点偶尔会略微越界，不夹会有爆音
    const s = Math.max(-1, Math.min(1, samples[i]))
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true)
    offset += 2
  }

  return new Blob([view], { type: 'audio/wav' })
}

/// 给界面用：把秒数说成「3″」。
export function formatSeconds(seconds: number): string {
  const s = Math.max(1, Math.round(seconds))
  return `${s}″`
}
