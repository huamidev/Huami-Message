#!/usr/bin/env python3
"""
本地假 Supabase 服务 —— 用来在还没有真账号时验证客户端代码。

【为什么需要它】

写 Supabase 客户端时有个两难：
  · 不连真的，就没法验证代码对不对（"写完就交"等于把 bug 留到以后）
  · 连真的，又得先注册账号

所以按真实 API 的形状起一个本地假服务。App 连它跑完整流程，
验的是：请求拼得对不对、请求头带没带、返回解析得对不对、
错误处理走不走得通。

它**不能**验证的：真实 Supabase 的行为细节（版本差异、边界情况）。
那些只能等接上真的才知道。

【用法】

    python3 tools/fake-supabase/server.py 54321

然后用启动参数让 App 连它：

    -supabaseURL http://127.0.0.1:54321 -supabaseKey test
"""

import json
import re
import sys
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

# 内存里的"数据库"
USERS = {}       # email -> {"id": uuid, "password": str}
PROFILES = {}    # user_id -> {"display_name", "avatar_seed", "invite_code"}

INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def make_invite_code() -> str:
    import random
    return "".join(random.choice(INVITE_ALPHABET) for _ in range(8))


class Handler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        # 默认的日志太吵，我们自己打
        pass

    # ---------- 工具 ----------

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return {}

    def _send(self, status: int, payload=None):
        body = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _log(self, note=""):
        auth = self.headers.get("Authorization", "")
        # 只打前 20 个字符 —— 就算是假服务，也别养成把凭证整个打进日志的习惯
        short = (auth[:20] + "…") if len(auth) > 20 else auth
        print(f"  {self.command} {self.path}")
        print(f"    apikey: {self.headers.get('apikey', '(无)')}")
        print(f"    authorization: {short or '(无)'}")
        if note:
            print(f"    {note}")

    def _session(self, email: str, user_id: str):
        """伪造一个 Supabase 风格的会话响应"""
        token = "fake-access-token-" + str(uuid.uuid4())[:8]
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_in": 3600,
            "expires_at": 9999999999,
            "refresh_token": "fake-refresh-token",
            "user": {
                "id": user_id,
                "email": email,
                "aud": "authenticated",
                "role": "authenticated",
            },
        }

    # ---------- 路由 ----------

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        self._log()

        # GET /rest/v1/profiles?select=*&id=eq.<uuid>&limit=1
        if parsed.path == "/rest/v1/profiles":
            user_id = None
            for value in query.get("id", []):
                if value.startswith("eq."):
                    user_id = value[3:]
            profile = PROFILES.get(user_id)
            if profile is None:
                print("    → 200 []（没有这个档案）")
                self._send(200, [])
            else:
                print(f"    → 200 档案 display_name={profile['display_name']}")
                self._send(200, [profile])
            return

        print("    → 404 没有这个接口")
        self._send(404, {"message": "Not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        body = self._body()
        self._log(f"body: { {k: (v if k != 'password' else '***') for k, v in body.items()} }")

        # ── 注册 ──
        if parsed.path == "/auth/v1/signup":
            email = (body.get("email") or "").lower()
            password = body.get("password") or ""
            if not email or not password:
                print("    → 422 邮箱或密码为空")
                self._send(422, {"message": "Email and password are required"})
                return
            if email in USERS:
                # 这是真实 Supabase 的原话
                print("    → 422 邮箱已注册")
                self._send(422, {"message": "User already registered"})
                return

            user_id = str(uuid.uuid4())
            USERS[email] = {"id": user_id, "password": password}
            # 真实环境里这行是数据库触发器干的（见 supabase/schema.sql）
            PROFILES[user_id] = {
                "id": user_id,
                "display_name": email.split("@")[0],
                "avatar_seed": 2,
                "invite_code": make_invite_code(),
            }
            print(f"    → 200 注册成功，档案邀请码 {PROFILES[user_id]['invite_code']}")
            self._send(200, self._session(email, user_id))
            return

        # ── 登录 ──
        if parsed.path == "/auth/v1/token":
            grant = query.get("grant_type", [""])[0]
            if grant != "password":
                print(f"    → 400 不支持的 grant_type={grant}")
                self._send(400, {"error": "unsupported_grant_type"})
                return

            email = (body.get("email") or "").lower()
            password = body.get("password") or ""
            record = USERS.get(email)
            if record is None or record["password"] != password:
                # 真实 Supabase 的原话，客户端靠它翻译成"邮箱或密码不对"
                print("    → 400 凭证不对")
                self._send(400, {"error": "invalid_grant",
                                 "error_description": "Invalid login credentials"})
                return

            print("    → 200 登录成功")
            self._send(200, self._session(email, record["id"]))
            return

        # ── 退出 ──
        if parsed.path == "/auth/v1/logout":
            print("    → 204 已退出")
            self._send(204)
            return

        # ── 发重置密码邮件 ──
        if parsed.path == "/auth/v1/recover":
            print("    → 200 假装发了邮件")
            self._send(200, {})
            return

        print("    → 404 没有这个接口")
        self._send(404, {"message": "Not found"})


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 54321
    print(f"假 Supabase 服务已启动：http://127.0.0.1:{port}")
    print("（Ctrl-C 停止）\n")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
