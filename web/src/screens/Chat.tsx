import { useCallback, useEffect, useRef, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { loadMessages, sendMessage, conversationKeyOf } from '../lib/api'
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
  onBack,
}: {
  session: Session
  conversation: Conversation
  onBack: () => void
}) {
  const myID = session.user.id
  const isGroup = conversation.kind === 'group'

  const [messages, setMessages] = useState<Message[]>([])
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const listRef = useRef<HTMLDivElement>(null)
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

  return (
    <div className="chat">
      <header className="topbar chat-topbar">
        <button className="icon-btn" onClick={onBack} title="返回">
          ‹
        </button>
        <h2>{conversation.name}</h2>
        <span style={{ width: 38 }} />
      </header>

      <div className="messages" ref={listRef} onScroll={onScroll}>
        {messages.map((m) => (
          <Bubble key={m.id} message={m} mine={m.sender_id === myID} conversation={conversation} />
        ))}
      </div>

      {error && <p className="msg error pad">{error}</p>}

      <form className="composer" onSubmit={send}>
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="说点什么…"
          autoComplete="off"
        />
        <button className="btn primary" type="submit" disabled={!draft.trim()}>
          发送
        </button>
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
}: {
  message: Message
  mine: boolean
  conversation: Conversation
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
    <div className={mine ? 'row mine' : 'row theirs'}>
      {!mine && (
        <Avatar name={conversation.name} seed={conversation.avatarSeed} url={conversation.avatarURL} size={34} />
      )}
      {mine && <span className="stamp">{time}</span>}
      <div className={mine ? 'bubble mine' : 'bubble theirs'}>{message.body}</div>
      {!mine && <span className="stamp">{time}</span>}
    </div>
  )
}
