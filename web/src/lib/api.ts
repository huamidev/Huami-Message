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
      username: p.username ?? undefined,
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

// ── 加好友 ─────────────────────────────────────────────────────────────

/// 用户名的规则，和 iOS 版一致：去掉开头的 @、转小写、去掉空白。
///
/// 为什么要统一在这一步做：用户会输入 "@Test002"、空格、"TEST002"，
/// 这些在他眼里都是同一个名字。不归一化的话，服务器会说"找不到"，
/// 而用户看着自己输的名字觉得明明是对的。
export function normalizeUsername(raw: string): string {
  return raw.trim().replace(/^@+/, '').toLowerCase().replace(/\s+/g, '').slice(0, 15)
}

export function usernameProblem(value: string): string | null {
  if (value.length === 0) return null
  if (value.length < 5) return '至少要 5 位'
  if (value.length > 15) return '最多 15 位'
  if (!/^[a-z0-9_]+$/.test(value)) return '只能用字母、数字和下划线'
  return null
}

/// 按用户名找人。
///
/// 找不到时**返回 null 而不是抛错** —— "这个人不存在"是一种正常结果，
/// 不是异常。调用方要的是"查到了就显示卡片，没查到就提示一句"。
export async function findProfile(username: string): Promise<Profile | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('username', username)
    .limit(1)
  if (error) throw error
  return (data?.[0] as Profile) ?? null
}

/// 发好友申请。
export async function sendFriendRequest(username: string, note: string | null): Promise<void> {
  const { error } = await supabase.rpc('send_friend_request', {
    target_username: username,
    note,
  })
  if (error) throw error
}

/// 我收到的、还没处理的申请。
export async function loadIncomingRequests(myID: UUID): Promise<
  { id: UUID; fromID: UUID; fromName: string; fromUsername: string; note: string | null }[]
> {
  const { data: rows, error } = await supabase
    .from('friend_requests')
    .select('*')
    .eq('to_id', myID)
    .eq('status', 'pending')
    .order('created_at', { ascending: false })
  if (error) throw error
  if (!rows?.length) return []

  // 申请人的资料：**一次查完**，不要一个申请查一次 ——
  // 那又是"N 条申请 N 次请求"。
  const ids = rows.map((r) => r.from_id as UUID)
  const { data: profiles, error: profileError } = await supabase
    .from('profiles')
    .select('*')
    .in('id', ids)
  if (profileError) throw profileError

  const byID = new Map((profiles ?? []).map((p) => [p.id as UUID, p as Profile]))
  return rows.flatMap((r) => {
    const p = byID.get(r.from_id as UUID)
    if (!p) return []   // 查不到资料就跳过这一条，不要整批失败
    return [{
      id: r.id as UUID,
      fromID: r.from_id as UUID,
      fromName: p.display_name || p.username || '某人',
      fromUsername: p.username ?? '',
      note: (r.note as string) ?? null,
    }]
  })
}

/// 同意 / 拒绝一条申请。
export async function respondToRequest(id: UUID, accept: boolean): Promise<void> {
  const { error } = await supabase.rpc('respond_friend_request', {
    request_id: id,
    accept,
  })
  if (error) throw error
}

// ── 群 ─────────────────────────────────────────────────────────────────

/// 建一个群。
///
/// 参数是**用户名数组** —— 服务器按 profiles.username 找人。
/// 找不到任何一个就整次回滚（服务器那边是这么写的），
/// 所以要么全进来，要么一个都不进来，不会出现"少了几个人还没提示"。
export async function createGroup(title: string, usernames: string[]): Promise<string> {
  const { data, error } = await supabase.rpc('create_group', {
    group_title: title,
    member_usernames: usernames,
  })
  if (error) throw error
  return data as string
}

/// 一个群里有哪些人。
export async function loadGroupMembers(
  conversationID: UUID,
): Promise<{ id: UUID; name: string; avatarSeed: number; role: string }[]> {
  const { data: members, error } = await supabase
    .from('conversation_members')
    .select('user_id, role')
    .eq('conversation_id', conversationID)
  if (error) throw error
  if (!members?.length) return []

  const ids = members.map((m) => m.user_id as UUID)
  const { data: profiles, error: profileError } = await supabase
    .from('profiles')
    .select('*')
    .in('id', ids)
  if (profileError) throw profileError

  // role 在成员表那份里，资料在 profiles 那份里 —— 按 id 拼起来
  const roleByID = new Map(members.map((m) => [m.user_id as UUID, m.role as string]))
  return (profiles ?? []).map((p) => ({
    id: p.id as UUID,
    name: p.display_name || p.username || '某人',
    avatarSeed: p.avatar_seed ?? 0,
    role: roleByID.get(p.id as UUID) ?? 'member',
  }))
}

// ── 文件上传 ───────────────────────────────────────────────────────────

/// 传一个文件上去，返回可以直接显示的网址。
///
/// 【路径的第一层必须是自己的用户 ID】
///
/// 存储的权限规则就是按这个判的：只能往"自己那一格"里写。
/// 换个人、或者换个路径格式，服务器会直接拒绝（403）。
/// 这是 iOS 版和网页版都必须遵守的同一条规矩。
export async function uploadChatFile(
  myID: UUID,
  blob: Blob,
  fileExtension: string,
  contentType: string,
): Promise<string> {
  const path = `${myID.toLowerCase()}/${crypto.randomUUID()}.${fileExtension}`
  const { error } = await supabase.storage
    .from('chat-images')
    .upload(path, blob, { contentType, cacheControl: '3600', upsert: false })
  if (error) throw error

  // 存进消息里的是**公开网址** —— 不含凭证.
  // 桶是公开读、按路径限制写的，所以这个网址谁拿到都能看。
  const { data } = supabase.storage.from('chat-images').getPublicUrl(path)
  return data.publicUrl
}

/// 发一条带附件的消息（图片 / 语音都用它）。
///
/// body 可以留空字符串 —— 图片消息没有文字内容，
/// 但数据库那一列是 not null，所以给个空串。
export async function sendAttachmentMessage(params: {
  myID: UUID
  conversationID: UUID
  isGroup: boolean
  body?: string
  imageURL?: string
  audioURL?: string
  audioSeconds?: number
}): Promise<Message> {
  const { data, error } = await supabase
    .from('messages')
    .insert({
      id: crypto.randomUUID(),
      sender_id: params.myID,
      recipient_id: params.isGroup ? null : params.conversationID,
      conversation_id: params.isGroup ? params.conversationID : null,
      body: params.body ?? '',
      image_url: params.imageURL ?? null,
      audio_url: params.audioURL ?? null,
      audio_seconds: params.audioSeconds ?? null,
    })
    .select()
    .single()
  if (error) throw error
  return data as Message
}

/// 把用户选的图片压小再传。
///
/// 【为什么必须压】
///
/// 现在手机随手拍一张就是 3～5 MB。直接传的话：
///   · 用户要等好几秒（还是在流量上）
///   · 服务器存储很快被占满
///   · 对方打开聊天页要下原图，一屏几张图就是十几 MB
///
/// 压到最长边 1600、JPEG 质量 0.8 —— 在手机屏上肉眼看不出区别，
/// 体积通常降到十分之一以内。
///
/// 用 canvas 做，不引任何图片处理库：浏览器自带的够用，
/// 而且不引入依赖就不会有"这个库更新了 API 变了"的问题。
export async function compressImage(file: File): Promise<Blob> {
  const MAX_EDGE = 1600
  const bitmap = await createImageBitmap(file)

  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height))
  const width = Math.round(bitmap.width * scale)
  const height = Math.round(bitmap.height * scale)

  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('这台设备的浏览器画不了图')
  ctx.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()

  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, 'image/jpeg', 0.8),
  )
  if (!blob) throw new Error('图片压缩失败')
  return blob
}

// ── 群管理 ─────────────────────────────────────────────────────────────

/// 改群名。**只有群主能改** —— 数据库那条 update 规则会拦下别人。
///
/// 别人改会得到 403（`new row violates row-level security policy`），
/// 那是正常的，不是 bug。界面上应该**不给非群主看这个入口**，
/// 而不是让他点了再报错。
export async function renameGroup(id: UUID, title: string): Promise<void> {
  const { error } = await supabase.from('conversations').update({ title }).eq('id', id)
  if (error) throw error
}

/// 往群里拉人（按用户名）。
export async function addGroupMembers(id: UUID, usernames: string[]): Promise<void> {
  const { error } = await supabase.rpc('add_group_members', {
    target_group: id,
    member_usernames: usernames,
  })
  if (error) throw error
}

/// 退群。群主退不了 —— 服务器会明确拒绝并说明原因。
export async function leaveGroup(id: UUID): Promise<void> {
  const { error } = await supabase.rpc('leave_group', { target_group: id })
  if (error) throw error
}

/// 撤回一条消息（两分钟内、自己发的）。
///
/// 撤回是**打标记**不是删数据 —— 两边都要看到"有过一条消息，被撤回了"。
/// 删掉的话，对面手机上那条还在，而发的人坚称没发过。
export async function recallMessage(id: UUID): Promise<void> {
  const { error } = await supabase
    .from('messages')
    .update({ recalled_at: new Date().toISOString() })
    .eq('id', id)
  if (error) throw error
}

/// 我自己的资料。
///
/// 【为什么必须从 profiles 里查，不能从登录会话里拿】
///
/// 这是个真 bug：网页版原来是从 `session.user.user_metadata.username`
/// 取用户名的，但**那个字段根本不存在**（Supabase 的 user_metadata 里
/// 只有 email / email_verified 这些）。于是代码回退成"邮箱的前缀" ——
/// 界面上显示 @huamidev，而真实用户名是 @huami。
///
/// 用户看到的是自己的名字，不会觉得有问题；但**二维码会照着这个错的
/// 名字生成**，朋友扫了根本加不上他。
///
/// 用户名的唯一真相在 profiles 表里。
export async function loadMyProfile(myID: UUID): Promise<Profile | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', myID)
    .maybeSingle()
  if (error) throw error
  return (data as Profile) ?? null
}
