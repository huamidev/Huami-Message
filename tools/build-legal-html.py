#!/usr/bin/env python3
"""
把 App 内的法律文本生成为可以直接托管的 HTML 页面。

【为什么要用生成而不是手写一份】
App 里显示的条款，和 App Store Connect 里填的"隐私政策 URL"，
**必须是同一份内容**。手抄两份，改一处忘另一处，迟早对不上 ——
审核员发现 App 内和网页上的政策不一致，是个很糟糕的信号。

所以：唯一的事实来源是 `Huami Message/Legal/LegalText.swift`，
这个脚本把它转成网页。

用法：
    python3 tools/build-legal-html.py

产物：
    docs/legal/privacy-policy.html
    docs/legal/terms-of-service.html

（放在 docs/legal/ 下，是因为 GitHub Pages 可以直接选 /docs 目录发布，
  这样两个页面的网址就是 https://<用户名>.github.io/<仓库名>/legal/xxx.html）
"""

import html
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Huami Message" / "Legal" / "LegalText.swift"
OUT_DIR = ROOT / "docs" / "legal"

DOCS = {
    "privacySections": ("privacy-policy", "隐私政策"),
    "termsSections": ("terms-of-service", "服务条款"),
}

PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Huami Message</title>
<style>
  :root {{
    --text: #1a1a1a; --text2: #5a5f66; --text3: #9aa0a6;
    --bg: #f2f3f5; --card: #fff; --line: #e8e9eb; --accent: #12b7f5;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 32px 20px 64px;
    background: var(--bg); color: var(--text);
    font: 16px/1.75 -apple-system, "PingFang SC", "Helvetica Neue", Arial, sans-serif;
    -webkit-text-size-adjust: 100%;
  }}
  main {{ max-width: 720px; margin: 0 auto; }}
  h1 {{ font-size: 26px; margin: 0 0 6px; }}
  .updated {{ color: var(--text3); font-size: 14px; margin: 0 0 28px; }}
  .card {{
    background: var(--card); border: 1px solid var(--line);
    border-radius: 12px; padding: 24px; margin-bottom: 16px;
  }}
  h2 {{ font-size: 17px; margin: 0 0 12px; }}
  p {{ color: var(--text2); margin: 0 0 12px; }}
  p:last-child {{ margin-bottom: 0; }}
  ul {{ margin: 0 0 12px; padding-left: 20px; }}
  li {{ color: var(--text2); margin-bottom: 6px; }}
  strong {{ color: var(--text); }}
  footer {{ color: var(--text3); font-size: 13px; text-align: center; margin-top: 28px; }}
  a {{ color: var(--accent); }}
</style>
</head>
<body>
<main>
  <h1>{title}</h1>
  <p class="updated">Huami Message · 生效日期：TODO（待填写）</p>
{sections}
  <footer>
    联系邮箱：TODO（待填写）<br>
    本页由 tools/build-legal-html.py 从 App 内文本生成，请勿手工编辑。
  </footer>
</main>
</body>
</html>
"""


def array_body(source: str, name: str) -> str:
    """取出 `private static let <name>: [Section] = [ ... ]` 里那对方括号之间的内容。

    【为什么要自己数括号，而不是用正则一把抓】
    第一版我用了 `source.index(name)` + 一个"看到下一个声明就停"的判断，
    结果 index 找到的是计算属性里那句 `Self.privacySections`（引用，不是声明），
    于是解析从错误的位置开始，只抓到 5 节（实际 8 节）。
    数括号虽然笨，但**位置是确定的**。
    """
    m = re.search(rf"private static let {name}\s*:\s*\[Section\]\s*=\s*\[", source)
    if not m:
        raise SystemExit(f"❌ 找不到 {name} 的声明")

    i = m.end()
    depth = 1
    start = i
    in_string = False
    while i < len(source) and depth > 0:
        c = source[i]
        if in_string:
            if c == "\\":
                i += 2          # 跳过转义字符
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return source[start:i]


def parse_sections(source: str, name: str):
    """从某个 sections 数组里取出 [(标题, [段落...]), ...]。"""
    body = array_body(source, name)
    sections = []
    for m in re.finditer(
        r'Section\(heading:\s*"([^"]*)",\s*paragraphs:\s*\[(.*?)\]\s*\)',
        body,
        re.S,
    ):
        heading = m.group(1)
        paras = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))
        sections.append((heading, paras))
    return sections


def render(sections) -> str:
    out = []
    for heading, paras in sections:
        items = []
        bullets = []
        for p in paras:
            text = html.escape(p)
            # 和 App 里一致：**粗体** 生效
            text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
            if p.startswith("- "):
                bullets.append(text[2:])
            else:
                if bullets:
                    items.append("<ul>" + "".join(f"<li>{b}</li>" for b in bullets) + "</ul>")
                    bullets = []
                items.append(f"<p>{text}</p>")
        if bullets:
            items.append("<ul>" + "".join(f"<li>{b}</li>" for b in bullets) + "</ul>")
        out.append(f'  <section class="card">\n    <h2>{html.escape(heading)}</h2>\n    '
                   + "\n    ".join(items) + "\n  </section>")
    return "\n".join(out)


def main():
    source = SOURCE.read_text(encoding="utf-8")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for name, (slug, title) in DOCS.items():
        sections = parse_sections(source, name)
        if not sections:
            raise SystemExit(f"❌ 没能从 {SOURCE.name} 里解析出 {name}")
        html_text = PAGE.format(title=title, sections=render(sections))
        path = OUT_DIR / f"{slug}.html"
        path.write_text(html_text, encoding="utf-8")
        print(f"  ✓ {path.relative_to(ROOT)}  （{len(sections)} 节）")


if __name__ == "__main__":
    main()
