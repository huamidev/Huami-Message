#!/usr/bin/env python3
"""
本地假 Supabase 服务 —— 用来在还没有真账号时验证客户端代码。

【为什么需要它】

写 Supabase 客户端时有个两难：
  · 不连真的，就没法验证代码对不对（"写完就交"等于把 bug 留到以后）
  · 连真的，又得先注册账号

所以按真实 API 的形状起一个本地假服务。App 连它跑完整流程。

它能验证的：请求拼得对不对、请求头带没带、过滤表达式写没写对、
返回解析得对不对、错误处理走不走得通。

【它验不了的】
真实 Supabase 的行为细节（版本差异、权限规则 RLS 到底拦不拦得住）。
那些只能等接上真的才知道。

【用法】

    python3 -u tools/fake-supabase/server.py 54321

然后用启动参数让 App 连它：

    -supabaseURL http://127.0.0.1:54321 -supabaseKey test
"""

import json
import random
import re
import sys
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

# ============================================================================
# 内存里的"数据库"
# ============================================================================

USERS = {}        # email -> {"id", "password"}
PROFILES = {}

# 假存储：bucket/路径 → (字节, Content-Type)
# 只为了让"发图片"这条链路能在本地跑通 —— 真存储的权限规则在这里测不了。
STORAGE = {}     # user_id -> {"id","display_name","avatar_seed","invite_code"}
FRIENDSHIPS = []  # [{"user_id","friend_id","blocked","created_at"}]
MESSAGES = []     # [{"id","sender_id","recipient_id","body","polished_with","created_at"}]

INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def now_iso():
    """带**微秒**的 ISO8601 —— 和真的 Postgres 一样。

    这一点很重要：客户端必须能解析 6 位小数的时间。
    假的这里如果只给毫秒，那个坑就永远测不出来。
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")


def make_invite_code():
    return "".join(random.choice(INVITE_ALPHABET) for _ in range(8))


# ============================================================================
# PostgREST 的过滤表达式解析
# ============================================================================
#
# 客户端会发这种查询：
#   or=(sender_id.eq.ME,recipient_id.eq.ME)
#   or=(and(sender_id.eq.ME,recipient_id.OTHER),and(...))
#   id=in.(a,b,c)
#
# 所以这里要真的把表达式解析成判定函数 —— 不能糊弄过去。
# 糊弄的话，"查询拼错了"这个最常见的 bug 就测不出来。

def split_top_level(text: str):
    """按顶层逗号切分，括号里的逗号不算"""
    parts, depth, current = [], 0, ""
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    if current:
        parts.append(current)
    return parts


def parse_filter(text: str):
    """把过滤表达式变成一个 row -> bool 的函数"""
    text = text.strip()
    # 容忍 "or=(...)" 这种带等号的写法（PostgREST 两种都出现在不同位置）
    text = re.sub(r"^(or|and)=", r"\1", text)

    if text.startswith("and(") and text.endswith(")"):
        fns = [parse_filter(p) for p in split_top_level(text[4:-1])]
        return lambda row: all(f(row) for f in fns)

    if text.startswith("or(") and text.endswith(")"):
        fns = [parse_filter(p) for p in split_top_level(text[3:-1])]
        return lambda row: any(f(row) for f in fns)

    if text.startswith("(") and text.endswith(")"):
        # 裸括号：PostgREST 里表示"其中任意一条成立"
        fns = [parse_filter(p) for p in split_top_level(text[1:-1])]
        return lambda row: any(f(row) for f in fns)

    # 叶子：col.op.value
    match = re.match(r"^([a-z_]+)\.(eq|neq|in)\.(.*)$", text)
    if not match:
        raise ValueError(f"看不懂的过滤表达式: {text}")
    col, op, value = match.groups()

    if op == "eq":
        return lambda row: str(row.get(col, "")).lower() == value.lower()
    if op == "neq":
        return lambda row: str(row.get(col, "")).lower() != value.lower()
    if op == "in":
        items = [v.strip().strip('"').lower() for v in value.strip("()").split(",")]
        return lambda row: str(row.get(col, "")).lower() in items

    raise ValueError(f"不支持的操作符: {op}")


def apply_query(rows, query):
    """把 PostgREST 的查询参数应用到一堆行上"""
    # 过滤。
    # 两种形状：
    #   or=(...) / and=(...)   —— 值是带括号的整段表达式，把关键字接上去就行
    #   user_id=eq.xxx         —— 值是"操作符.值"，前面补上列名
    for key, values in query.items():
        if key in ("select", "order", "limit", "offset"):
            continue
        for value in values:
            expr = f"{key}{value}" if key in ("or", "and") else f"{key}.{value}"
            fn = parse_filter(expr)
            rows = [r for r in rows if fn(r)]

    # 排序
    if "order" in query:
        spec = query["order"][0]
        field, _, direction = spec.partition(".")
        rows = sorted(rows, key=lambda r: str(r.get(field, "")), reverse=(direction == "desc"))

    # 限量
    if "limit" in query:
        rows = rows[: int(query["limit"][0])]

    return rows


# ============================================================================
# HTTP
# ============================================================================

class Handler(BaseHTTPRequestHandler):

    # 用 HTTP/1.1 —— 分块传输（chunked）要求它。
    # 流式响应必须分块发，否则客户端要等整个响应结束才拿得到数据，
    # "打字机效果"就变成了"等十秒然后一次性出现"。
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass   # 用我们自己的日志

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return {}

    def _send(self, status, payload=None):
        body = b"" if payload is None else json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _log(self, note=""):
        auth = self.headers.get("Authorization", "")
        short = (auth[:22] + "…") if len(auth) > 22 else auth
        print(f"  {self.command} {self.path}")
        print(f"    apikey={self.headers.get('apikey', '(无)')}  auth={short or '(无)'}")
        if note:
            print(f"    {note}")

    # ---------- 流式响应（SSE）----------

    def _stream_start(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        # 分块传输：不告诉客户端总长度，边算边发
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

    def _stream_send(self, obj):
        """发一条 SSE 事件"""
        payload = f"data: {json.dumps(obj, ensure_ascii=False)}\n\n".encode()
        self.wfile.write(f"{len(payload):X}\r\n".encode() + payload + b"\r\n")
        self.wfile.flush()

    def _stream_end(self):
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def _me(self):
        """从 Authorization 头里认出"我是谁"（假服务里直接查 token 表）"""
        return TOKENS.get(self.headers.get("Authorization", "").replace("Bearer ", ""))

    # ---------- 读 ----------

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/storage/v1/object/public/"):
            key = parsed.path.replace("/object/public/", "/object/", 1)
            item = STORAGE.get(key)
            if item is None:
                self._send(404, {"message": "Object not found"})
                return
            body, content_type = item
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        parsed = urlparse(self.path)
        query = parse_qs(parsed.query, keep_blank_values=True)
        self._log()

        try:
            if parsed.path == "/rest/v1/profiles":
                rows = apply_query(list(PROFILES.values()), query)
                print(f"    → 200 {len(rows)} 条档案")
                self._send(200, rows)
                return

            if parsed.path == "/rest/v1/friendships":
                me = self._me()
                rows = [r for r in FRIENDSHIPS if r["user_id"] == me]
                rows = apply_query(rows, query)
                print(f"    → 200 {len(rows)} 个好友关系")
                self._send(200, rows)
                return

            if parsed.path == "/rest/v1/messages":
                rows = apply_query(list(MESSAGES), query)
                print(f"    → 200 {len(rows)} 条消息")
                self._send(200, rows)
                return

        except ValueError as e:
            print(f"    → 400 过滤表达式有问题：{e}")
            self._send(400, {"message": str(e)})
            return

        print("    → 404 没有这个接口")
        self._send(404, {"message": "Not found"})

    # ---------- 写 ----------

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/storage/v1/object/"):
            # 直接读原始字节：图片是二进制，不能当 JSON 解
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
            content_type = self.headers.get("Content-Type") or "application/octet-stream"
            STORAGE[parsed.path] = (body, content_type)
            print(f"    → 200 收到 {len(body)} 字节 → {parsed.path}")
            self._send(200, {"Key": parsed.path.split("/")[-1]})
            return

        parsed = urlparse(self.path)
        query = parse_qs(parsed.query, keep_blank_values=True)
        body = self._body()
        self._log(f"body={ {k: (v if k != 'password' else '***') for k, v in body.items()} }")

        # ── 注册 ──
        if parsed.path == "/auth/v1/signup":
            email = (body.get("email") or "").lower()
            password = body.get("password") or ""
            if not email or not password:
                self._send(422, {"message": "Email and password are required"})
                return
            if email in USERS:
                print("    → 422 邮箱已注册")
                self._send(422, {"message": "User already registered"})
                return

            user_id = str(uuid.uuid4())
            USERS[email] = {"id": user_id, "password": password}
            # 真实环境里这行是数据库触发器干的（见 supabase/schema.sql）
            PROFILES[user_id] = {
                "id": user_id,
                "display_name": email.split("@")[0],
                "avatar_seed": random.randint(0, 5),
                "invite_code": make_invite_code(),
                # 真服务器上这一列是后加的（要用户跑 alter table）。
                # 假服务器直接给上，方便验证"改简介"这条链路。
                "bio": "",
            }
            print(f"    → 200 注册成功，邀请码 {PROFILES[user_id]['invite_code']}")
            self._send(200, self._session(email, user_id))
            return

        # ── 登录 ──
        if parsed.path == "/auth/v1/token":
            email = (body.get("email") or "").lower()
            password = body.get("password") or ""
            record = USERS.get(email)
            if record is None or record["password"] != password:
                print("    → 400 凭证不对")
                self._send(400, {"error": "invalid_grant",
                                 "error_description": "Invalid login credentials"})
                return
            print("    → 200 登录成功")
            self._send(200, self._session(email, record["id"]))
            return

        if parsed.path in ("/auth/v1/logout", "/auth/v1/recover"):
            print(f"    → 204/200 {parsed.path} 成功")
            self._send(204 if "logout" in parsed.path else 200, None if "logout" in parsed.path else {})
            return

        # ── 发消息 ──
        if parsed.path == "/rest/v1/messages":
            me = self._me()
            if me is None:
                print("    → 401 没认出你是谁")
                self._send(401, {"message": "JWT 无效"})
                return

            row = {
                "id": body.get("id") or str(uuid.uuid4()),
                "sender_id": body.get("sender_id"),
                "recipient_id": body.get("recipient_id"),
                "body": body.get("body"),
                # ⚠️ 这一行漏过一次：假服务器原来是手写字段列表回传的，
                # 加 image_url 时忘了补，于是 App 把服务器的回传存回本地、
                # 把刚上传好的图片地址覆盖成了空。
                # 现象特别迷惑：服务器日志里明明收到了 image_url，
                # 界面上却是一条空消息。真 Supabase 会回传完整行，不会这样。
                "image_url": body.get("image_url"),
                "polished_with": body.get("polished_with"),
                # 服务器写的时间才是权威的
                "created_at": now_iso(),
            }
            MESSAGES.append(row)
            print(f"    → 201 存下一条消息（{len(MESSAGES)} 条）")

            # 客户端带了 Prefer: return=representation 就把整行回传
            if "return=representation" in (self.headers.get("Prefer") or ""):
                self._send(201, [row])
            else:
                self._send(201, None)
            return

        # ── 用邀请码加好友（对应 schema.sql 里的数据库函数）──
        if parsed.path == "/rest/v1/rpc/add_friend_by_invite":
            me = self._me()
            code = (body.get("code") or "").upper()
            target = next((p for p in PROFILES.values() if p["invite_code"] == code), None)
            if target is None:
                print(f"    → 400 邀请码 {code} 不存在")
                self._send(400, {"message": "邀请码不存在"})
                return
            if target["id"] == me:
                self._send(400, {"message": "不能加自己"})
                return

            for a, b in ((me, target["id"]), (target["id"], me)):
                if not any(f["user_id"] == a and f["friend_id"] == b for f in FRIENDSHIPS):
                    FRIENDSHIPS.append({"user_id": a, "friend_id": b,
                                        "blocked": False, "created_at": now_iso()})
            print(f"    → 200 加好友成功：{target['display_name']}")
            self._send(200, target["id"])
            return

        # ── AI 云函数（真实现是 Supabase Edge Function 里那个 ai-proxy）──
        if parsed.path == "/functions/v1/ai-proxy":
            import time

            mode = body.get("mode")
            self._stream_start()

            if mode == "ping":
                # 和真云函数一样：直接回，不调用 AI（探针不该花钱）
                print("    → 200 探针 pong")
                self._stream_send({"type": "pong"})
                self._stream_send({"type": "done"})
                self._stream_end()
                return

            if mode == "polish":
                # 润色：把一整句切碎，一小段一小段发 —— 模拟模型的流式输出
                style = body.get("style")
                samples = {
                    "tactful": "昨天没看到你，是临时有事吗？大家等到挺晚的，都有点担心你。",
                    "concise": "昨天怎么没来？大家等了很久。",
                    "warm": "昨天没见到你，还有点担心。要是遇到什么事，随时跟我说。",
                }
                text = samples.get(style, samples["tactful"])
                print(f"    → 200 流式润色（{style}），共 {len(text)} 字")
                for i in range(0, len(text), 4):
                    self._stream_send({"type": "text", "value": text[i:i + 4]})
                    time.sleep(0.06)
                self._stream_send({"type": "done"})
                self._stream_end()
                return

            if mode == "advise":
                intent = body.get("intent")
                # 故意在一次响应里发 status + 多个 block + recommendation，
                # 和真云函数的事件形状完全一致
                events = [
                    {"type": "status", "value": "正在读这段对话"},
                    {"type": "block", "value": {
                        "kind": "options",
                        "title": "当前真实意图",
                        "prompt": "他是在等你解释吗？",
                        "options": [
                            {"label": "不是，他要的是态度", "percent": 79, "isRecommended": True},
                            {"label": "是", "percent": 21},
                        ],
                    }},
                    {"type": "block", "value": {
                        "kind": "level",
                        "prompt": "这件事的严重程度",
                        "level": 6,
                        "levelCaption": "危险等级",
                    }},
                    {"type": "block", "value": {
                        "kind": "options",
                        "prompt": "现在解释原因有用吗？",
                        "options": [
                            {"label": "没用，听着像找借口", "percent": 85, "isRecommended": True},
                            {"label": "有用", "percent": 15},
                        ],
                    }},
                    {"type": "recommendation",
                     "value": "回的时候先接住情绪，再讲事实。**第一句里不要出现「因为」**。"},
                ]
                print(f"    → 200 流式判断（{intent}），{len(events)} 个事件")
                for event in events:
                    self._stream_send(event)
                    time.sleep(0.4)
                self._stream_send({"type": "done"})
                self._stream_end()
                return

            print(f"    → 400 不认识的 mode={mode}")
            self._stream_send({"type": "done"})
            self._stream_end()
            return

        print("    → 404 没有这个接口")
        self._send(404, {"message": "Not found"})

    # ---------- 改数据（PostgREST 的 PATCH）----------

    def do_PATCH(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query, keep_blank_values=True)
        body = self._body()
        self._log(f"PATCH body={body}")

        if parsed.path == "/rest/v1/profiles":
            me = self._me()
            target = None
            for value in query.get("id", []):
                if value.startswith("eq."):
                    target = value[3:]
            if target is None or target != me:
                print("    → 403 只能改自己那行")
                self._send(403, {"message": "只能改自己的资料"})
                return

            profile = PROFILES.get(target)
            if profile is None:
                self._send(404, {"message": "找不到这个档案"})
                return

            # 只更新传上来的字段
            changed = []
            for key in ("display_name", "bio", "avatar_seed"):
                if key in body:
                    profile[key] = body[key]
                    changed.append(key)
            print(f"    → 200 改了 {changed}")

            if "return=representation" in (self.headers.get("Prefer") or ""):
                self._send(200, [profile])
            else:
                self._send(204, None)
            return

        print("    → 404 没有这个接口")
        self._send(404, {"message": "Not found"})

    # ---------- 会话 ----------

    def _session(self, email, user_id):
        token = "fake-token-" + str(uuid.uuid4())[:8]
        TOKENS[token] = user_id
        return {
            "access_token": token,
            "token_type": "bearer",
            "expires_in": 3600,
            "refresh_token": "fake-refresh-token",
            "user": {"id": user_id, "email": email, "aud": "authenticated", "role": "authenticated"},
        }


TOKENS = {}   # access_token -> user_id


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 54321
    print(f"假 Supabase 服务已启动：http://127.0.0.1:{port}")
    print("（Ctrl-C 停止）\n")
    # ⚠️ 必须用 ThreadingHTTPServer（多线程），不能用 HTTPServer（单线程）。
    #
    # 因为我把协议设成了 HTTP/1.1，浏览器/客户端默认会**复用连接**（keep-alive）。
    # 单线程服务器在一个连接关闭之前不会去处理别的连接 ——
    # 于是 App 并发发三个润色请求时，只有第一个能通，另外两个永远排着队。
    #
    # 这个坑很隐蔽：它看起来像"客户端并发有问题"，其实是测试工具的限制。
    # 真实服务器当然支持并发，所以这里也要像个真实服务器。
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
