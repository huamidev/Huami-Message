#!/usr/bin/env bash
#
# 一条命令部署到 Cloudflare Pages。
#
# 用法：
#     cd web
#     ./deploy.sh
#
# 第一次会打开浏览器让你登录 Cloudflare —— 点一下授权就行，
# 之后就不用再登了。
#
# 【为什么不用手动拖 dist 文件夹】
#
# 拖拽也能用，但每次改完都得重新拖，而且很容易忘掉"先 npm run build"。
# 这个脚本按顺序做三件事，少一步就报错停下：
#     ① 装依赖（第一次才真的装，之后是秒过）
#     ② 构建（失败就停 —— 绝不把半成品推上去）
#     ③ 部署
#
# 【部署完记得做的一件事】
#
# 去 Supabase 后台 → Authentication → URL Configuration → Redirect URLs，
# 把新网址加进白名单。
#
# 不加的话，注册时的确认邮件点回来会**跳不回你的网站** ——
# 而登录本身不受影响，所以这个坑要等到有人注册才会暴露。

set -euo pipefail        # 任何一步失败就停，不要带着错继续往下走

cd "$(dirname "$0")"

PROJECT_NAME="${1:-huami-message}"

echo "▸ 装依赖…"
npm install --silent

echo "▸ 构建…"
npm run build

if [ ! -f dist/index.html ]; then
  echo "✗ 构建完了却没看到 dist/index.html —— 不往下走了"
  exit 1
fi

echo "▸ 部署到 Cloudflare Pages（项目名：$PROJECT_NAME）…"
npx wrangler pages deploy dist --project-name "$PROJECT_NAME"

echo
echo "✓ 完成。上面那一行就是你的网址。"
echo
echo "⚠️ 别忘了：Supabase → Authentication → URL Configuration → Redirect URLs"
echo "   把新网址加进去，否则注册确认邮件点回来会失败。"
