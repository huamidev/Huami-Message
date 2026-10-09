import { supabase } from './supabase'
import { SUPABASE_URL, SUPABASE_KEY } from './config'

/// AI 的入口。
///
/// 【为什么这里不用 supabase-js，而是自己 fetch】
///
/// AI 的回复是**一段一段流出来的**（服务器发 SSE，一个字一个字到）。
/// 那种"看着它写出来"的感觉是这个功能的体验核心 ——
/// 等它全部写完再一次性显示，用户要盯着空屏好几秒。
///
/// supabase-js 的 functions.invoke 会把整个响应读完再给你，
/// 拿不到中间的片段。所以这里直接 fetch，自己读流。

/// 润色的三种风格。和 iOS 版的 PolishStyle 一一对应 ——
/// rawValue 必须一模一样，服务器是按这个字符串分支的。
export type PolishStyle = 'tactful' | 'concise' | 'warm'

export const POLISH_STYLES: { id: PolishStyle; title: string; hint: string }[] = [
  { id: 'tactful', title: '更得体', hint: '把话说圆，适合工作、长辈、不太熟的人' },
  { id: 'concise', title: '更简短', hint: '砍掉啰嗦，只说重点' },
  { id: 'warm', title: '更有温度', hint: '加一点关心，适合在乎的人' },
]

/// 小助手：看一段对话，给判断和建议。
///
/// 和润色走同一个云函数、同一条 SSE 通道，只是 mode 不同。
/// 它发回来的不是文字，而是几种结构化的"方块"——
/// 因为"他什么意思"这种问题，一句话说不清，
/// 用几个带概率的选项反而更接近人真实的判断方式。
export type AssistantIntent = 'explain' | 'reply' | 'draft'

export const ASSISTANT_INTENTS: { id: AssistantIntent; title: string }[] = [
  { id: 'explain', title: '他什么意思？' },
  { id: 'reply', title: '我该怎么回？' },
  { id: 'draft', title: '帮我起草' },
]

export interface DecisionOption {
  label: string
  percent: number
  isRecommended?: boolean
}

export interface DecisionBlock {
  kind: 'options' | 'level'
  title?: string
  prompt: string
  options?: DecisionOption[]
  level?: number
}

export type AssistantEvent =
  | { type: 'status'; value: string }
  | { type: 'block'; value: DecisionBlock }
  | { type: 'recommendation'; value: string }

/// 让小助手看一段对话。
export async function advise(params: {
  friendName: string
  intent: AssistantIntent
  /// 只发最近若干条 —— 这是对用户的隐私承诺，不能只是说说
  messages: { mine: boolean; text: string }[]
  onEvent: (event: AssistantEvent) => void
}): Promise<void> {
  await streamAI(
    {
      mode: 'advise',
      friend_name: params.friendName,
      intent: params.intent,
      messages: params.messages,
    },
    (event) => {
      const type = event?.type
      if (type === 'status' && typeof event.value === 'string') {
        params.onEvent({ type: 'status', value: event.value })
      } else if (type === 'block' && event.value) {
        params.onEvent({ type: 'block', value: event.value as DecisionBlock })
      } else if (type === 'recommendation' && typeof event.value === 'string') {
        params.onEvent({ type: 'recommendation', value: event.value })
      }
      // text / done 不属于助手，忽略
    },
  )
}

/// 润色一句话。每收到一段就回调一次 `onChunk`。
///
/// 返回一个可以取消的对象 —— 用户点了别的风格或者关掉面板时，
/// 上一次请求要能停下来，否则两段文字会交错着往外冒。
export async function polish(
  text: string,
  style: PolishStyle,
  onChunk: (piece: string) => void,
): Promise<void> {
  await streamAI({ mode: 'polish', text, style }, (event) => {
    if (event?.type === 'text' && typeof event.value === 'string') onChunk(event.value)
  })
}

/// 调 AI 云函数并把 SSE 一条条解出来。
///
/// 【为什么两个功能共用一个函数】
///
/// 润色和小助手走的是同一个云函数、同一条 SSE 通道，只是 mode 不同。
/// 读流的逻辑（buffer、半行、跨域、401）一模一样 ——
/// 写两遍就意味着以后修一个 bug 要记得修两处。
export async function streamAI(
  body: Record<string, unknown>,
  onEvent: (event: any) => void,
): Promise<void> {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new Error('还没登录')

  const response = await fetch(`${SUPABASE_URL}/functions/v1/ai-proxy`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${token}`,
    },
    // 字段名是下划线 —— 服务器（Deno）那边就是按这个读的
    body: JSON.stringify(body),
  })

  if (!response.ok) {
    if (response.status === 404) {
      // 404 在这条链路上只有一个原因，说清楚比让用户去猜好
      throw new Error('AI 云函数还没部署。')
    }
    const detail = await response.text()
    throw new Error(detail.slice(0, 160) || `请求失败（${response.status}）`)
  }
  if (!response.body) throw new Error('服务器没有返回内容')

  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  // 按行读。SSE 的格式是 "data: {...}\n"，但一次 read 可能只拿到半行，
  // 所以要留一个 buffer 把断掉的半行拼起来再解析。
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })

    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''          // 最后一段可能是半行，留到下一轮
    for (const line of lines) {
      const event = parseLine(line)
      if (event) onEvent(event)
    }
  }
  // 收尾：万一最后一行没有换行符
  const tail = parseLine(buffer)
  if (tail) onEvent(tail)
}

/// 解析一行 SSE，取出文字片段。
///
/// 服务器可能发这几种 type：
///   text            正文片段 ← 我们要的
///   status          进度提示（"正在思考"之类）
///   block / recommendation   小助手用的，润色用不到
///   done            结束
///
/// **不认识的 type 一律忽略**，不要抛错 ——
/// 服务器以后加了新类型，老客户端不该因此崩掉。
function parseLine(line: string): any | null {
  const trimmed = line.trim()
  if (!trimmed.startsWith('data:')) return null
  const payload = trimmed.slice(5).trim()
  if (!payload || payload === '[DONE]') return null

  try {
    return JSON.parse(payload)
  } catch {
    // 解析不了就当没有 —— 一行坏数据不该毁掉整段对话
    return null
  }
}
