// ============================================================================
// Huami Message · AI 中转云函数
// ============================================================================
//
// 【这个文件是干什么的】
//
// 它是一个"传话人"：App 把要问 AI 的内容发给它，它加上 API Key 再去问 DeepSeek，
// 然后把结果一段段转发回 App。
//
// 【为什么必须有它 —— 这是整个项目最重要的一条安全规则】
//
// API Key **绝对不能写进 App**。App 装到手机上就是一个压缩包，
// 任何人解开来都能看到里面的字符串。Key 一旦泄露，
// 别人会拿它刷 token，**账单是你的**。
//
// 所以 Key 只存在这个云函数的环境变量里（Supabase 后台设置），
// App 那边只认识这个函数的网址，永远看不到 Key。
//
// 【部署】
//
//   supabase functions deploy ai-proxy
//   supabase secrets set DEEPSEEK_API_KEY=sk-你的一串密钥
//
// Supabase 会自动注入 SUPABASE_URL / SUPABASE_ANON_KEY，不用手动设。
//
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const DEEPSEEK_MODEL = "deepseek-chat";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  try {
    const payload = await req.json();

    // ── ⓪ 探针（**放在鉴权之前**）──
    //
    // 它只回一句 pong、不碰数据库也不调用 AI，所以让未登录的请求也能问。
    //
    // 为什么要这样：App 的「服务器自检」是在**登录页**跑的（那时候还没登录）。
    // 探针如果要求先登录，自检就永远拿不到"函数在不在"的答案 ——
    // 未部署时它会看到 401 而不是 404，于是漏报，
    // 用户就只能对着小助手的报错发呆。
    if (payload?.mode === "ping") {
      return new Response(
        `data: ${JSON.stringify({ type: "pong" })}\n\ndata: ${JSON.stringify({ type: "done" })}\n\n`,
        { headers: { ...CORS, "Content-Type": "text/event-stream" } },
      );
    }

    // ── ① 确认调用者是登录用户 ──
    // 不校验的话，任何人知道这个网址就能白用你的额度。
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "缺少登录凭证" }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      (Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY"))!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return json({ error: "登录已失效，请重新登录" }, 401);
    }

    // ── ② 读参数（payload 在上面已经解析过了）──

    // ── 用谁的密钥：**用户自己填的优先** ──
    //
    // 这样朋友可以拿自己的 DeepSeek 账号用，花自己的钱。
    // 对搭这个 App 的人来说，这是把成本交还给真正在用的人 ——
    // 否则所有朋友的 AI 账单都压在一个人头上，人数一多就撑不住。
    //
    // 密钥只用于这一次请求，**不落库、不打日志**。
    const personalKey = (req.headers.get("x-deepseek-key") ?? "").trim();
    const apiKey = personalKey.length > 10
      ? personalKey
      : Deno.env.get("DEEPSEEK_API_KEY");
    if (!apiKey) {
      return json({ error: "没有可用的 AI 密钥" }, 500);
    }

    const { messages, stream: shouldStream } = buildMessages(payload);

    // ── ③ 去问 DeepSeek（要求它流式回答）──
    const upstream = await fetch(DEEPSEEK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        messages,
        stream: true,
        temperature: 0.7,
      }),
    });

    if (!upstream.ok || !upstream.body) {
      const detail = await upstream.text();
      // 注意：这里只记录状态码和返回体，**绝不要把 apiKey 打出来**
      console.error("DeepSeek 调用失败", upstream.status, detail.slice(0, 500));
      return json({ error: "AI 服务暂时不可用" }, 502);
    }

    // ── ④ 把上游的 SSE 转成我们自己的简单格式，转发给 App ──
    //
    // App 那边的解析逻辑越简单越好。所以这里做一层转换：
    // 上游是 OpenAI 那种复杂的 SSE，我们转成三种极简事件。
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    const out = new ReadableStream({
      async start(controller) {
        const reader = upstream.body!.getReader();
        let sseBuffer = "";     // 上游 SSE 的粘包缓冲
        let lineBuffer = "";    // 模型输出里"还没收到换行"的那半行
        let sawFirstBlock = false;

        const send = (obj: unknown) =>
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));

        /// 试着把一行解析成事件推出去。
        /// 解析不了就丢掉 —— 模型偶尔会多说一句人话，不该让整个流崩掉。
        const emitLine = (raw: string) => {
          const line = raw.trim()
            .replace(/^```(?:json)?/i, "")
            .replace(/```$/, "")
            .trim();
          if (!line || !line.startsWith("{")) return;
          try {
            const obj = JSON.parse(line);
            if (typeof obj.status === "string") {
              send({ type: "status", value: obj.status });
            } else if (typeof obj.recommendation === "string") {
              send({ type: "recommendation", value: obj.recommendation });
            } else if (typeof obj.kind === "string") {
              sawFirstBlock = true;
              send({ type: "block", value: obj });
            }
          } catch {
            // 不是合法 JSON 的一行，忽略
          }
        };

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            sseBuffer += decoder.decode(value, { stream: true });
            const sseLines = sseBuffer.split("\n");
            sseBuffer = sseLines.pop() ?? "";

            for (const sseLine of sseLines) {
              if (!sseLine.startsWith("data: ")) continue;
              const data = sseLine.slice(6).trim();
              if (data === "[DONE]") continue;

              let delta: string | undefined;
              try {
                delta = JSON.parse(data).choices?.[0]?.delta?.content;
              } catch {
                continue;
              }
              if (!delta) continue;

              if (!shouldStream) {
                lineBuffer += delta;   // 润色那种只要一整段，攒着最后一起发
                continue;
              }

              // 逐行切：**只有收到换行才说明这一行是完整的 JSON**
              lineBuffer += delta;
              const parts = lineBuffer.split("\n");
              lineBuffer = parts.pop() ?? "";
              for (const part of parts) emitLine(part);
            }
          }
        } catch (e) {
          console.error("转发中断", e);
        } finally {
          if (!shouldStream) {
            send({ type: "text", value: lineBuffer.trim() });
          } else if (lineBuffer.trim()) {
            // 最后一行可能没有换行结尾，补一次
            emitLine(lineBuffer);
          }
          send({ type: "done" });
          controller.close();
          reader.releaseLock();
        }
      },
    });

    return new Response(out, {
      headers: { ...CORS, "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
    });
  } catch (e) {
    console.error("ai-proxy 出错", e);
    return json({ error: "服务器内部错误" }, 500);
  }
});

// ============================================================================
// 提示词
// ============================================================================
//
// 【这一段是整个产品"聪不聪明"的真正所在】
// 界面、数据库、网络都是管道；用户感受到的质量，几乎全在这里。
// 所以它值得反复调 —— 而且调它**不需要动任何界面代码**。

// deno-lint-ignore no-explicit-any
function buildMessages(payload: any): { messages: any[]; stream: boolean } {
  const mode = payload?.mode;

  // ── 模块一：润色 ──
  // 铁律：**只发这一句话，不读聊天记录**。这是我们对用户的承诺。
  if (mode === "polish") {
    const text = String(payload.text ?? "").slice(0, 500);
    const style = payload.style;
    const guide: Record<string, string> = {
      tactful: "把话说圆，让对方不觉得被冒犯。适合工作、长辈、不太熟的人。",
      concise: "砍掉啰嗦，只说重点。保留全部关键信息，但句子更短。",
      warm: "加一点关心和情绪，让话听起来有温度。适合在乎的人。",
    };
    return {
      stream: false,
      messages: [
        {
          role: "system",
          content:
            `你是中文表达助手。用户会给你一句话，你要改写它：${guide[style] ?? guide.tactful}\n\n` +
            `铁律：\n` +
            `1. 只输出改写后的那一句话，不要任何解释、不要引号、不要"改写："这类前缀。\n` +
            `2. 保持原意，不要增加原文没有的信息，不要编造细节。\n` +
            `3. 长度和原文接近，不要膨胀成一段话。\n` +
            `4. 用简体中文。`,
        },
        { role: "user", content: text },
      ],
    };
  }

  // ── 模块二：小助手（决策模型）──
  //
  // 【输出格式：每行一个 JSON 对象】
  //
  // 为什么不用"一个大 JSON 数组"：那样必须等整个输出结束才能解析，
  // 用户要盯着转圈等好几秒。改成一行的粒度之后，
  // **每收满一行就能立刻推出一个方块**，方块一个一个冒出来。
  //
  // 这也让解析变得极简：按换行切，切出来的每一行都是完整 JSON。
  // 代价只是要求模型别把 JSON 换行写 —— 一个句子里加进这个约束，很容易做到。
  const intent = payload?.intent ?? "reply";
  const friendName = String(payload?.friendName ?? "对方").slice(0, 20);
  const lines: string[] = (payload?.messages ?? [])
    .slice(-10) // 安全兜底：无论如何不超过 10 条
    .map((m: { mine: boolean; text: string }) =>
      `${m.mine ? "我" : friendName}：${String(m.text).slice(0, 300)}`
    );

  const intents: Record<string, string> = {
    explain: `判断${friendName}最后那句话**真正想表达什么**。不要给回复建议。`,
    reply: `判断${friendName}那句话的意思，并指出这条回复该说什么。`,
    draft: `判断现在适不适合用户先开口，并给出起头的方向。`,
  };

  const formatRules =
    `输出格式（必须严格遵守，每行一个 JSON 对象，行与行之间不要有空行）：\n` +
    `第一行：{"status":"正在读这段对话"}\n` +
    `之后 3-5 行，每行一个方块，两种形态：\n` +
    `  选项型：{"kind":"options","title":"可选的小标题","prompt":"问题","options":[{"label":"选项","percent":79,"isRecommended":true},{"label":"选项","percent":21}]}\n` +
    `  量级型：{"kind":"level","prompt":"一句话","level":6,"levelCaption":"危险等级"}\n` +
    `最后一行：{"recommendation":"一条具体动作"}\n\n` +
    `硬性要求：\n` +
    `1. **每个选项型方块里的 percent 加起来必须正好等于 100**。\n` +
    `2. 至少有一个量级型方块（level 是 0-10 的整数）。\n` +
    `3. percent 高的那一项要标 isRecommended: true。\n` +
    `4. recommendation 必须是**具体动作**，不能是"多沟通""好好说"这种废话。\n` +
    `5. 不要输出 JSON 以外的东西，不要加代码块标记。\n`;

  return {
    stream: true,
    messages: [
      {
        role: "system",
        content:
          `你是一个中文沟通顾问，帮用户把话说好。\n\n` +
          `你**不写回复**，你只做判断：判断对方在想什么、现在该做什么。\n` +
          `语气像一个懂人情世故的朋友。说人话，不要"首先其次最后"，不要客套。\n` +
          `允许用**两个星号**包住要强调的短语。\n\n` +
          formatRules,
      },
      {
        role: "user",
        content:
          `我和${friendName}最近的对话：\n\n${lines.join("\n")}\n\n` +
          `请${intents[intent] ?? intents.reply}`,
      },
    ],
  };
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
