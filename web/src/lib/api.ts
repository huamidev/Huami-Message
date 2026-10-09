import { supabase } from './supabase'
import type { Conversation, Message, Profile, UUID } from './types'

/// 和服务器打交道的地方，都收在这一个文件里。
///
/// 【为什么不让组件直接调 supabase】
///
/// 组件里散落着查询，改一个字段名要满项目找。收在一处之后：
///   · 表结构变了只改这里
///   · 想加日志、加缓存也只有一处要动
///   · 测试的时候可以整个换掉
///
/// 这和后端那几个 Swift 文件的思路是一样的。

// ── 会话列表 ───────────────────────────────────────────────────────────

/// 拉出"我的会话列表"：好友 + 群，按最近说话时间从新到旧。
///
/// 【为什么要分好几步查，而不是让数据库 JOIN】
///
/// 因为权限规则（RLS）是按行判的，JOIN 出来的中间结果会很别扭。
/// iOS 版走的是同一套路子：先查"我和谁有关系"，再按 id 把资料查回来。
/// 好处是每一步都简单、都能单独看懂，坏处是多几次往返 ——
/// 对几十个好友的规模来说，这点往返可以忽略。
export async function loadConversations(myID: UUID): Promise<Conversation[]> {
  // ① 我的好友关系
  const { data: links, error: linkError } = await supabase
    .from('friendships')
    .select('friend_id, blocked')
    .eq('user_id', myID)
  if (linkError) throw linkError

  // ② 我参与的群
  const { data: memberships, error: memberError } = await supabase
    .from('conversation_members')
    .select('conversation_id, last_read_at')
    .eq('user_id', myID)
  if (memberError) throw memberError

  const friendIDs = (links ?? []).map((l) => l.friend_id as UUID)
  const groupIDs = (memberships ?? []).map((m) => m.conversation_id as UUID)

  // ③ 好友的资料（昵称、头像色）
  const { data: profiles, error: profileError } = friendIDs.length
    ? await supabase.from('profiles').select('*').in('id', friendIDs)
    : { data: [] as Profile[], error: null }
  if (profileError) throw profileError

  // ④ 群的信息
  const { data: groups, error: groupError } = groupIDs.length
    ? await supabase.from('conversations').select('*').in('id', groupIDs)
    : { data: [] as any[], error: null }
  if (groupError) throw groupError

  // ⑤ 每个会话的最后一条消息 —— **一次查回来，不要每个会话查一次**
  //
  // 一次拉最近 300 条，然后在内存里按会话分组取第一条。
  // 300 条足够覆盖"每个会话至少有一条"的场景；
  // 会话特别多、又很久没说话的那种，预览会显示成空 —— 可以接受。
  const recent = await loadRecentMessages(myID, groupIDs, 300)

  // 按"属于哪段会话"分组，每组第一条就是最新的（上面已经按时间倒序）
  const lastByConversation = new Map<UUID, Message>()
  for (const m of recent) {
    const key = conversationKeyOf(m, myID)
    if (key && !lastByConversation.has(key)) lastByConversation.set(key, m)
  }

  const direct: Conversation[] = (profiles ?? []).map((p) => {
    const last = lastByConversation.get(p.id)
    return {
      id: p.id,
      kind: 'direct' as const,
      title: null,
      name: p.display_name || p.username || '未命名',
      avatarSeed: p.avatar_seed ?? 0,
      avatarURL: p.avatar_url,
      lastMessage: last ? preview(last) : '',
      lastTime: last?.created_at ?? '',
      unread: 0,
    }
  })

  const groupList: Conversation[] = (groups ?? []).map((g) => {
    const last = lastByConversation.get(g.id)
    return {
      id: g.id,
      kind: 'group' as const,
      title: g.title,
      name: g.title || '群聊',
      avatarSeed: g.avatar_seed ?? 0,
      avatarURL: null,
      lastMessage: last ? preview(last) : '',
      lastTime: last?.created_at ?? '',
      unread: 0,
    }
  })

  return [...direct, ...groupList].sort((a, b) => (a.lastTime < b.lastTime ? 1 : -1))
}

/// 最近的消息。一次查询拿回来。
async function loadRecentMessages(
  myID: UUID,
  groupIDs: UUID[],
  limit: number,
): Promise<Message[]> {
  // or 里面可以套 in —— 但列表为空时不能拼出空的 in()，那会是个语法错误
  const parts = [`sender_id.eq.${myID}`, `recipient_id.eq.${myID}`]
  if (groupIDs.length) parts.push(`conversation_id.in.(${groupIDs.join(',')})`)

  const { data, error } = await supabase
    .from('messages')
    .select('*')
    .or(parts.join(','))
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as Message[]
}

/// 一条消息属于哪段会话。
///
/// 群消息看 conversation_id；一对一要判断"对方是谁" ——
/// 我发出去的那条，recipient 才是会话；别人发来的那条，sender 才是。
export function conversationKeyOf(m: Message, myID: UUID): UUID | null {
  if (m.conversation_id) return m.conversation_id
  if (!m.recipient_id) return null
  return m.sender_id === myID ? m.recipient_id : m.sender_id
}

/// 列表里那一行小字。
export function preview(m: Message): string {
  if (m.recalled_at) return '[已撤回]'
  if (m.audio_url) return '[语音]'
  if (m.image_url) return '[图片]'
  return m.body || ''
}

// ── 消息 ───────────────────────────────────────────────────────────────

/// 拉一段会话的历史消息，按时间从早到晚。
export async function loadMessages(
  myID: UUID,
  conversationID: UUID,
  isGroup: boolean,
  limit = 200,
): Promise<Message[]> {
  const query = supabase.from('messages').select('*')
  const filtered = isGroup
    ? query.eq('conversation_id', conversationID)
    : query.or(
        `and(sender_id.eq.${myID},recipient_id.eq.${conversationID}),` +
          `and(sender_id.eq.${conversationID},recipient_id.eq.${myID})`,
      )

  const { data, error } = await filtered
    .order('created_at', { ascending: true })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as Message[]
}

/// 发一条消息。
export async function sendMessage(params: {
  myID: UUID
  conversationID: UUID
  isGroup: boolean
  body: string
}): Promise<Message> {
  const row = {
    // ⚠️ **id 必须客户端生成。**
    //
    // 这一列在数据库里**没有默认值**（iOS 版一直是自己生成 UUID 的，
    // 所以从来没暴露）。不写的话服务器直接拒收：
    //
    //     null value in column "id" of relation "messages"
    //     violates not-null constraint
    //
    // 而且自己生成还有个好处：**画到界面上的那条和存进服务器的
    // 就是同一个 id**，服务器实时推回来的时候一比对就知道是同一条，
    // 不用靠"内容相同"去猜。
    id: crypto.randomUUID(),
    sender_id: params.myID,
    recipient_id: params.isGroup ? null : params.conversationID,
    conversation_id: params.isGroup ? params.conversationID : null,
    body: params.body,
  }
  const { data, error } = await supabase.from('messages').insert(row).select().single()
  if (error) throw error
  return data as Message
}
