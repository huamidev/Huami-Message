import { useCallback, useEffect, useRef, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import {
  loadMessages, sendMessage, conversationKeyOf,
  uploadChatFile, sendAttachmentMessage, compressImage,
  recallMessage,
} from '../lib/api'
import { startRecording, formatSeconds } from '../lib/audio'
import PolishSheet from '../components/PolishSheet'
import GroupInfo from './GroupInfo'
import AssistantSheet from '../components/AssistantSheet'
import type { Conversation, Message } from '../lib/types'
import Avatar from '../components/Avatar'

/// 聊天界面。
///
/// 【三个必须做对的地方 —— 也是 iOS 版踩过坑的地方】
///
/// ① **发出去要立刻出现在屏幕上**（optimistic）。
///    等服务器回执再画的话，用户按完发送会愣一下 —— 那种"卡"最难受。
///    所以先插一条"发送中"的，服务器回了再换成真的。
///
/// ② **自动滚到底，但别抢用户的滚动**。
///    用户正在往上翻旧消息时，来了新消息不能把他拽回去。
///
/// ③ **别人的消息一定有头像，自己的一个都没有**（用户定的规矩）。
export default function Chat({
  session,
  conversation,
  friends = [],
  onBack,
  onChanged = () => {},
}: {
  session: Session
  conversation: Conversation
  friends?: Conversation[]
  onBack: () => void
  onChanged?: () => void
}) {
  const myID = session.user.id
  const isGroup = conversation.kind === 'group'

  const [messages, setMessages] = useState<Message[]>([])
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [recording, setRecording] = useState(false)
  const [showPolish, setShowPolish] = useState(false)
  const [showInfo, setShowInfo] = useState(false)
  /// 长按哪条消息了（弹出撤回/删除）
  const [actionFor, setActionFor] = useState<Message | null>(null)
  /// 右上角的 ⋯ 菜单开着吗
  const [showMenu, setShowMenu] = useState(false)
  const [showAssistant, setShowAssistant] = useState(false)
  const recorderRef = useRef<ReturnType<typeof startRecording> | null>(null)

  const fileRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)
  /// 有没有草稿 —— 有才显示润色按钮（空的时候点它没有意义）
  const hasDraft = draft.trim().length > 0
  /// 用户是不是"贴着底部"。不贴的时候来新消息就不自动滚。
  const stickToBottom = useRef(true)

  // ── 加载历史 ──
  useEffect(() => {
    let cancelled = false
    loadMessages(myID, conversation.id, isGroup)
      .then((list) => {
        if (!cancelled) setMessages(list)
      })
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
    return () => {
      cancelled = true
    }
  }, [myID, conversation.id, isGroup])

  // ── 实时收新消息 ──
  useEffect(() => {
    const channel = supabase
      .channel(`chat-${conversation.id}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'messages' },
        (payload) => {
          const incoming = payload.new as Message
          // 这段会话的才收 —— 订阅是整张表的，得自己筛
          if (conversationKeyOf(incoming, myID) !== conversation.id) return
          setMessages((prev) => {
            // 同一个 id 已经在了 → 替换。
            //
            // 这一步同时解决两件事：
            //   · 我自己发的那条：界面上先画了一条（**id 一样**），
            //     服务器推回来时把它换成服务器那份
            //   · 撤回这类「更新」：服务器推的是同一 id 的新版本
            //
            // 因为 id 是客户端生成的，这两种情况不用区分对待。
            //
            // （原来这里还有一段"内容相同就当成同一条"的兜底 ——
            //   id 对上之后它就是死代码了，删掉。靠内容猜是危险的：
            //   对方完全可能真的说了同样的话。）
            if (prev.some((m) => m.id === incoming.id)) {
              return prev.map((m) => (m.id === incoming.id ? incoming : m))
            }
            return [...prev, incoming]
          })
        },
      )
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [conversation.id, myID])

  // ── 自动滚到底 ──
  //
  // 依赖 messages.length：新消息进来、或者历史加载完，都要贴到底。
  // 但只有用户本来就贴着底部时才滚（否则他正在翻旧消息，会被拽走）。
  useEffect(() => {
    const el = listRef.current
    if (!el || !stickToBottom.current) return
    el.scrollTop = el.scrollHeight
  }, [messages.length])

  const onScroll = useCallback(() => {
    const el = listRef.current
    if (!el) return
    // 离底部 80 像素以内就算"贴着底"
    stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  }, [])

  // ── 发送 ──
  async function send(e: React.FormEvent) {
    e.preventDefault()
    const text = draft.trim()
    if (!text || sending) return

    setDraft('')
    setError(null)
    stickToBottom.current = true

    // ① 先画到界面上
    const temp: Message = {
      // ⚠️ id 和真正发出去的那条**一模一样**（都是客户端生成的）。
      //    这样服务器实时推回来时，一比对 id 就知道是同一条，
      //    不用靠"内容相同"去猜 —— 内容相同可能是对方真的也说了同样的话。
      id: crypto.randomUUID(),
      sender_id: myID,
      recipient_id: isGroup ? null : conversation.id,
      conversation_id: isGroup ? conversation.id : null,
      body: text,
      image_url: null,
      audio_url: null,
      audio_seconds: null,
      polished_with: null,
      recalled_at: null,
      created_at: new Date().toISOString(),
      mine: true,
    }
    setMessages((prev) => [...prev, temp])
    setSending(true)

    try {
      const saved = await sendMessage({
        myID,
        conversationID: conversation.id,
        isGroup,
        body: text,
      })
      // ② 服务器回执到了，把临时那条换成真的
      setMessages((prev) => prev.map((m) => (m.id === temp.id ? saved : m)))
    } catch (err) {
      // ③ 失败就把那条标出来，并且**把内容还给输入框** ——
      //    用户打了一段话，不能因为网络问题就让他重打一遍
      setMessages((prev) => prev.filter((m) => m.id !== temp.id))
      setDraft(text)
      setError(err instanceof Error ? err.message : '发送失败')
    } finally {
      setSending(false)
    }
  }

  /// 录一条语音。
  ///
  /// 【为什么是"点一下开始、再点一下结束"，而不是 iOS 那样的按住说话】
  ///
  /// 手机上"按住"很自然，但**手机浏览器里按住会遇到滚动、长按选中、
  /// 系统菜单**这些干扰 —— 一不小心语音就断了，或者弹出一个菜单。
  ///
  /// 所以网页版用点击式：点一下开始（按钮变成"停止"），再点一下结束。
  /// 多一次点击，换来的是"一定能录完"。
  async function toggleRecording() {
    setError(null)

    // 正在录 → 结束并发送
    if (recording && recorderRef.current) {
      const rec = recorderRef.current
      recorderRef.current = null
      setRecording(false)
      stickToBottom.current = true
      setUploading(true)
      try {
        const { blob, seconds } = await rec.stop()
        // 太短的多半是误触，直接丢掉（不到半秒连"喂"都说不完）
        if (seconds < 0.5) return
        const url = await uploadChatFile(myID, blob, 'wav', 'audio/wav')
        const saved = await sendAttachmentMessage({
          myID, conversationID: conversation.id, isGroup,
          audioURL: url, audioSeconds: seconds,
        })
        setMessages((prev) => [...prev, saved])
      } catch (err) {
        if (err instanceof Error && err.message !== 'cancelled') {
          setError(err.message)
        }
      } finally {
        setUploading(false)
      }
      return
    }

    // 没在录 → 开始
    try {
      recorderRef.current = startRecording()
      setRecording(true)
    } catch {
      setError('拿不到麦克风权限。检查一下浏览器的设置。')
    }
  }

  /// 撤回一条消息。
  ///
  /// 先改界面再去服务器 —— 反过来的话，用户点完要等一个来回才看到变化。
  /// 服务器失败就**改回去**：不能让界面显示"已撤回"而对面还看得见，
  /// 那比撤回失败更糟（用户以为抹掉了，其实没有）。
  async function doRecall(message: Message) {
    setActionFor(null)
    const before = messages
    setMessages((prev) =>
      prev.map((m) => (m.id === message.id ? { ...m, recalled_at: new Date().toISOString() } : m)),
    )
    try {
      await recallMessage(message.id)
    } catch (err) {
      setMessages(before)
      setError(err instanceof Error ? err.message : '撤回失败，可能已经超过两分钟了。')
    }
  }

  /// 选了一张图 → 压缩 → 上传 → 发出去。
  ///
  /// 全程给用户看着：压缩和上传加起来可能要一两秒，
  /// 期间什么都不显示的话，用户会以为没点上、又点一次。
  async function pickImage(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ''            // 清掉，这样选同一张图也能再触发一次
    if (!file) return

    setError(null)
    stickToBottom.current = true
    setUploading(true)
    try {
      const blob = await compressImage(file)
      const url = await uploadChatFile(myID, blob, 'jpg', 'image/jpeg')
      const saved = await sendAttachmentMessage({
        myID, conversationID: conversation.id, isGroup, imageURL: url,
      })
      setMessages((prev) => [...prev, saved])
    } catch (err) {
      setError(err instanceof Error ? err.message : '图片发送失败')
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="chat">
      {actionFor && (
        <div className="sheet-backdrop" onClick={() => setActionFor(null)}>
          <div className="sheet" onClick={(e) => e.stopPropagation()}>
            <div className="quote">{actionFor.body || (actionFor.image_url ? '[图片]' : '[语音]')}</div>
            {canRecall(actionFor, myID) && (
              <button className="btn danger" onClick={() => doRecall(actionFor)}>撤回</button>
            )}
            {!canRecall(actionFor, myID) && (
              <p className="muted small">
                只能撤回两分钟内、自己发的消息。
              </p>
            )}
            <button className="btn ghost" onClick={() => setActionFor(null)}>取消</button>
          </div>
        </div>
      )}

      {showMenu && (
        <div className="sheet-backdrop" onClick={() => setShowMenu(false)}>
          <div className="sheet" onClick={(e) => e.stopPropagation()}>
            <button className="btn ghost" onClick={() => { setShowMenu(false); setShowAssistant(true) }}>
              ✨ 小助手：分析这段对话
            </button>
            {isGroup && (
              <button className="btn ghost" onClick={() => { setShowMenu(false); setShowInfo(true) }}>
                👥 群聊信息
              </button>
            )}
            <button className="btn ghost" onClick={() => setShowMenu(false)}>取消</button>
          </div>
        </div>
      )}

      {showAssistant && (
        <AssistantSheet
          messages={messages}
          friendName={conversation.name}
          onClose={() => setShowAssistant(false)}
        />
      )}

      {showInfo && (
        <GroupInfo
          session={session}
          group={conversation}
          friends={friends}
          onBack={() => setShowInfo(false)}
          onChanged={() => { onChanged() }}
        />
      )}

      {showPolish && (
        <PolishSheet
          original={draft.trim()}
          onUse={(text) => { setDraft(text); setShowPolish(false) }}
          onClose={() => setShowPolish(false)}
        />
      )}

      <header className="topbar chat-topbar">
        <button className="icon-btn" onClick={onBack} title="返回">
          ‹
        </button>
        <h2>{conversation.name}</h2>
        <button className="icon-btn" onClick={() => setShowMenu(true)} title="更多">⋯</button>
      </header>

      <div className="messages" ref={listRef} onScroll={onScroll}>
        {messages.map((m) => (
          <Bubble
            key={m.id}
            message={m}
            mine={m.sender_id === myID}
            conversation={conversation}
            onLongPress={() => setActionFor(m)}
          />
        ))}
      </div>

      {error && <p className="msg error pad">{error}</p>}

      {uploading && <p className="muted small pad">图片发送中…</p>}

      <form className="composer" onSubmit={send}>
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          style={{ display: 'none' }}
          onChange={pickImage}
        />
        <button
          type="button"
          className="icon-btn"
          onClick={() => fileRef.current?.click()}
          title="发图片"
        >
          📎
        </button>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="说点什么…"
          autoComplete="off"
        />
        {hasDraft && (
          <button
            type="button"
            className="icon-btn"
            onClick={() => setShowPolish(true)}
            title="帮我润色"
          >
            ✨
          </button>
        )}
        {hasDraft ? (
          <button className="btn primary" type="submit">发送</button>
        ) : (
          <button
            type="button"
            className={recording ? 'btn danger' : 'icon-btn'}
            onClick={toggleRecording}
            title={recording ? '结束并发送' : '按住说话'}
          >
            {recording ? '结束' : '🎤'}
          </button>
        )}
      </form>
    </div>
  )
}

/// 一条消息。
///
/// 布局和 iOS 版一致：
///   对方的：  [头像] [气泡] [时间]        ← 时间在气泡右边
///   自己的：           [时间] [气泡]      ← 时间在气泡左边
///
/// 也就是时间永远贴在"对话中间"那一侧，而不是贴着屏幕边缘。
function Bubble({
  message,
  mine,
  conversation,
  onLongPress,
}: {
  message: Message
  mine: boolean
  conversation: Conversation
  onLongPress: () => void
}) {
  if (message.recalled_at) {
    return (
      <div className="recalled">{mine ? '你撤回了一条消息' : '对方撤回了一条消息'}</div>
    )
  }

  const time = new Date(message.created_at).toLocaleTimeString('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
  })

  return (
    <div
      className={mine ? 'row mine' : 'row theirs'}
      /* 手机上长按会触发 contextmenu，桌面上是右键 —— 两个都覆盖到。
         用长按而不是给每条消息加一个按钮：聊天界面里每多一个按钮，
         就少一分"在看对话"的感觉。 */
      onContextMenu={(e) => { e.preventDefault(); onLongPress() }}
    >
      {!mine && (
        <Avatar name={conversation.name} seed={conversation.avatarSeed} url={conversation.avatarURL} size={34} />
      )}
      {mine && <span className="stamp">{time}</span>}
      <div className={mine ? 'bubble mine' : 'bubble theirs'}>
        {message.image_url && (
          <img className="bubble-image" src={message.image_url} alt="" loading="lazy" />
        )}
        {/* 用浏览器自带的播放器：它认得 m4a、webm、wav，
            以后不管 iOS 那边发什么格式过来都能直接播 */}
        {message.audio_url && (
          <span className="voice">
            <audio controls preload="metadata" src={message.audio_url} />
            <span className="stamp">{formatSeconds(message.audio_seconds ?? 0)}</span>
          </span>
        )}
        {message.body && <span>{message.body}</span>}
      </div>
      {!mine && <span className="stamp">{time}</span>}
    </div>
  )
}

/// 这条能不能撤回：我发的、还没撤回、且在两分钟内。
///
/// 判据和服务器那条规则一致（客户端判一次是为了即时反馈，
/// 服务器还要再判一次 —— 客户端的时间可以被绕过）。
function canRecall(message: Message, myID: string): boolean {
  if (message.sender_id !== myID) return false
  if (message.recalled_at) return false
  return Date.now() - new Date(message.created_at).getTime() < 120_000
}
