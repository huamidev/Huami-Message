# 网页版

安卓朋友也能用的那一版。和 iOS 版共用同一个 Supabase 后端
（表结构、权限规则、登录、实时、存储、AI 云函数都是同一套）。

## 本地跑

```bash
npm install      # 第一次才需要
npm run dev      # 打开 http://localhost:5173
```

想看**和线上完全一样**的版本：

```bash
npm run build
npm run preview
```

## 自检（**改完东西先跑这个**）

```bash
npm run build && npm run preview &     # 先起正式版
node tools/browser-check.mjs           # 主流程 18 项
node tools/invite-check.mjs            # 邀请链接 5 项
```

**用真浏览器跑真流程**：登录 → 会话列表 → 聊天 → 发消息 → 撤回 →
看大图 → 删单条 → 小助手 → 群资料 → 联系人 → 二维码解码 → 资料页。

⚠️ 默认**不会**发消息（`--send` 才发）。因为自检用的是真实账号、
真实会话 —— 发出去的消息会留在聊天记录里，而且删不掉
（消息表没有删除权限，那是为了不让任何一方单方面抹掉记录）。

## 一些踩过的坑（都在代码注释里，这里列个目录）

| 坑 | 在哪 |
|---|---|
| 消息 id 必须客户端生成（数据库那列没有默认值） | `lib/api.ts` |
| 用户名只能从 `profiles` 查，不能从登录会话猜 | `lib/api.ts` |
| 上传路径第一层必须是自己的 id（存储权限按这个判） | `lib/api.ts` |
| 二维码里装链接不是纯用户名（否则相机不认） | `screens/Contacts.tsx` |
| 未读/已删按账号分开存（共用 key 会串） | `lib/readState.ts` |
| Service Worker 绝不缓存后端请求 | `public/sw.js` |
| 头像圆角方形不是圆形（抄 iOS 的设计） | `styles.css` |
| 一堆数值直接来自 iOS 的 `Design/Theme.swift` | `styles.css` 顶部 |

## 部署

见 `../docs/23-网页版部署.md`。

**配置要点**（连 Git 那条路）：Root directory = `web`、
Build command = `npm run build`、Deploy command 保持 `npx wrangler deploy`。
项目名必须和 `wrangler.toml` 里的 `name` 一致。
