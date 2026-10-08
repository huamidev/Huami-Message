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

/// 分析文字和建议之间的分隔标记。
/// 为什么要这么绕：AI 只能吐文字，但我们有两种不同性质的东西要传 ——
/// 分析（要一个字一个字显示）和建议（每条后面要挂按钮）。
/// 用一个不会自然出现的标记切开，比让 AI 输出严格 JSON 稳得多
/// （JSON 少一个引号就整段废了）。
const SPLIT_MARKER = "<<<SUGGESTIONS>>>";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

  try {
    // ── ① 确认调用者是登录用户 ──
    // 不校验的话，任何人知道这个网址就能白用你的额度。
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "缺少登录凭证" }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return json({ error: "登录已失效，请重新登录" }, 401);
    }

    // ── ② 读参数 ──
    const payload = await req.json();
    const apiKey = Deno.env.get("DEEPSEEK_API_KEY");
    if (!apiKey) {
      return json({ error: "服务器没有配置 DEEPSEEK_API_KEY" }, 500);
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
        let buffer = "";
        let full = "";
        let sentText = "";        // 已经转发出去的分析文字（用来算"还差多少没发"）
        let markerSeen = false;

        const send = (obj: unknown) =>
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`));

        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() ?? "";

            for (const line of lines) {
              if (!line.startsWith("data: ")) continue;
              const data = line.slice(6).trim();
              if (data === "[DONE]") continue;

              try {
                const chunk = JSON.parse(data);
                const delta = chunk.choices?.[0]?.delta?.content;
                if (!delta) continue;

                full += delta;

                if (shouldStream) {
                  if (markerSeen) {
                    // 已经在建议区了，文字部分不再转发
                    continue;
                  }
                  // ⚠️ 这里必须判断"整段到目前为止"而不是"这一块"。
                  //    模型完全可能把「分析结尾 + 分隔标记 + JSON 开头」
                  //    塞进同一个数据块里 —— 那就得把标记之前的部分发完、
                  //    之后的部分**先存着**，等收全了再解析成建议。
                  //    我第一版没考虑这个，会在 JSON 只收到一个 "[" 时就去解析。
                  const markerAt = full.indexOf(SPLIT_MARKER);
                  if (markerAt === -1) {
                    send({ type: "text", value: delta });
                    sentText += delta;
                  } else {
                    markerSeen = true;
                    const upToMarker = full.slice(0, markerAt);
                    const remaining = upToMarker.slice(sentText.length);
                    if (remaining) {
                      send({ type: "text", value: remaining });
                      sentText = upToMarker;
                    }
                  }
                }
              } catch {
                // 上游偶尔会发心跳之类的东西，忽略
              }
            }
          }
        } catch (e) {
          console.error("转发中断", e);
        } finally {
          if (!shouldStream) {
            // 润色这种"只要一整段"的，最后一次性发
            send({ type: "text", value: full.trim() });
          } else if (markerSeen) {
            // 收全了才解析建议 —— 到这里 JSON 一定是完整的
            const after = full.slice(full.indexOf(SPLIT_MARKER) + SPLIT_MARKER.length);
            send({ type: "suggestions", value: parseSuggestions(after) });
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

  // ── 模块二：小助手 ──
  const intent = payload?.intent ?? "reply";
  const friendName = String(payload?.friendName ?? "对方").slice(0, 20);
  const lines: string[] = (payload?.messages ?? [])
    .slice(-10) // 安全兜底：无论如何不超过 10 条
    .map((m: { mine: boolean; text: string }) =>
      `${m.mine ? "我" : friendName}：${String(m.text).slice(0, 300)}`
    );

  const intents: Record<string, string> = {
    explain: `先分析${friendName}最后那句话**真正想表达什么**（字面意思之下的意思）。不要给回复建议。`,
    reply: `先简短分析${friendName}那句话的意思（2-3 句），然后给出 3 条可以直接发出去的回复。`,
    draft: `帮用户起 3 个开头，用来主动跟${friendName}说一件不太好开口的事。`,
  };

  return {
    stream: true,
    messages: [
      {
        role: "system",
        content:
          `你是一个中文沟通顾问，帮用户把话说好。\n\n` +
          `语气要求：像一个懂人情世故的朋友在给建议。说人话，不要"首先其次最后"，` +
          `不要小标题，不要客套。中文标点。\n\n` +
          `输出格式（必须严格遵守）：\n` +
          `1. 先输出分析文字，用**两个星号**包住要强调的短语。\n` +
          (intent === "explain"
            ? `2. 只输出分析，不要输出任何建议，也不要输出分隔标记。\n`
            : `2. 然后另起一行输出这个标记：${SPLIT_MARKER}\n` +
              `3. 标记之后输出一个 JSON 数组，里面是 3 个字符串，` +
              `每个字符串是一条可以直接发出去的完整中文消息（不要编号、不要引号）。\n` +
              `4. JSON 之后不要再输出任何东西。\n`),
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

/// 从模型输出的尾巴里抠出那个 JSON 数组。
/// 模型有时会在 JSON 前后多写几个字，所以做一次"从第一个 [ 到最后一个 ]"的容错。
function parseSuggestions(raw: string): string[] {
  const start = raw.indexOf("[");
  const end = raw.lastIndexOf("]");
  if (start === -1 || end === -1 || end <= start) return [];
  try {
    const arr = JSON.parse(raw.slice(start, end + 1));
    return Array.isArray(arr) ? arr.filter((x) => typeof x === "string").slice(0, 3) : [];
  } catch {
    return [];
  }
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
