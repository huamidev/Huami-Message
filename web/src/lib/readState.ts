/// 每个会话"我读到哪儿了"。
///
/// 【为什么存在 localStorage，而不是数据库】
///
/// "读到哪儿了"是**一台设备上的事**：我在手机上看了，不等于我在电脑上也看了。
/// 放进数据库会让两个设备的红点互相干扰 —— 在 A 读过的，B 上的红点就没了，
/// 而 B 根本没显示过。
///
/// 真要做跨设备的已读，那是"已读回执"（对方能看到你读没读），
/// 是完全不同的一个功能，不在这一版范围内。
///
/// ⚠️ **按账号分开存。** key 里带上用户 id ——
/// iOS 版就是因为本地数据没按账号隔离，出过"换个账号左右全反"的 bug。
/// 那种 bug 的根源都是"两份本该分开的数据共用了一个 key"。

const PREFIX = 'huami.lastRead'

function key(userID: string, conversationID: string): string {
  return `${PREFIX}.${userID}.${conversationID}`
}

/// 上次读到什么时间（毫秒）。没读过返回 0。
export function getLastRead(userID: string, conversationID: string): number {
  const raw = localStorage.getItem(key(userID, conversationID))
  const value = raw ? Number(raw) : 0
  return Number.isFinite(value) ? value : 0
}

/// 记下"我读到这会儿了"。
export function markRead(userID: string, conversationID: string, at = Date.now()): void {
  localStorage.setItem(key(userID, conversationID), String(at))
}

/// 一段会话里有多少条是"我还没看过的"。
///
/// 只数**别人发的** —— 自己发的不算未读（那是我自己刚做的事）。
export function countUnread(
  userID: string,
  conversationID: string,
  messages: { sender_id: string; created_at: string }[],
): number {
  const since = getLastRead(userID, conversationID)
  return messages.filter(
    (m) => m.sender_id !== userID && new Date(m.created_at).getTime() > since,
  ).length
}
