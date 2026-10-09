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

/// 润色一句话。每收到一段就回调一次 `onChunk`。
///
/// 返回一个可以取消的对象 —— 用户点了别的风格或者关掉面板时，
/// 上一次请求要能停下来，否则两段文字会交错着往外冒。
export async function polish(
  text: string,
  style: PolishStyle,
  onChunk: (piece: string) => void,
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
    body: JSON.stringify({ mode: 'polish', text, style }),
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
      const piece = parseLine(line)
      if (piece) onChunk(piece)
    }
  }
  // 收尾：万一最后一行没有换行符
  const tail = parseLine(buffer)
  if (tail) onChunk(tail)
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
function parseLine(line: string): string | null {
  const trimmed = line.trim()
  if (!trimmed.startsWith('data:')) return null
  const payload = trimmed.slice(5).trim()
  if (!payload || payload === '[DONE]') return null

  try {
    const event = JSON.parse(payload)
    if (event?.type === 'text' && typeof event.value === 'string') return event.value
    return null
  } catch {
    // 解析不了就当没有 —— 一行坏数据不该毁掉整段对话
    return null
  }
}
