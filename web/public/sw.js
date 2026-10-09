/// Service Worker：让"添加到主屏幕"之后像 App 一样打开。
///
/// 【它只做两件事】
///
///   ① 把 App 的壳（HTML、JS、CSS、图标）缓存下来 ——
///      第二次打开不用再下载，也不怕网络抽风
///   ② 别的什么都不碰
///
/// 【为什么"别的什么都不碰"要单独强调】
///
/// 后端请求（Supabase 那个域名）**绝对不能缓存**。
///
/// 聊天数据是有时效的：缓存了的话，用户会看到几分钟前的消息列表，
/// 还以为对方没回他 —— 这比"打不开"更糟，因为它**看起来是正常的**。
///
/// 所以下面那个 fetch 处理器第一步就把跨域请求排除掉。

const CACHE = 'huami-shell-v1'
const SHELL = ['./', './index.html', './manifest.webmanifest',
               './icon-192.png', './icon-512.png', './apple-touch-icon.png']

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', (event) => {
  // 清掉旧版本的缓存，不然升级之后用户可能拿到一半新一半旧的东西
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const request = event.request
  const url = new URL(request.url)

  // ① 不是自己站点的，一律放过去（Supabase、AI 云函数……）
  if (url.origin !== self.location.origin) return
  // ② 只管 GET
  if (request.method !== 'GET') return

  // ③ 页面导航：先走网络（拿到最新版本），失败了再用缓存兜底
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).catch(() => caches.match('./index.html').then((r) => r ?? Response.error())),
    )
    return
  }

  // ④ 静态资源：先给缓存（快），同时在后台更新（下次就是新的）
  //
  // 为什么不用 cache-first 一把梭：Vite 打出来的文件名带哈希，
  // 内容一变文件名就变，所以缓存的永远不会过时 —— 可以放心先给缓存。
  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone()
            caches.open(CACHE).then((cache) => cache.put(request, copy))
          }
          return response
        })
        .catch(() => cached ?? Response.error())
      return cached ?? network
    }),
  )
})
