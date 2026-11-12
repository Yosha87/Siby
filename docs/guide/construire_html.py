#!/usr/bin/env python3
"""Builds docs/guide/USER_GUIDE.html (a readable page with the screenshots)
from docs/guide/USER_GUIDE.md. Images stay in docs/guide/img/."""
import pathlib, re
import markdown

ICI = pathlib.Path(__file__).resolve().parent
md = (ICI / "USER_GUIDE.md").read_text(encoding="utf-8")
corps = markdown.markdown(md, extensions=["tables", "toc", "attr_list"])

# figures: an image alone in a paragraph becomes a figure with its caption
corps = re.sub(r'<p><img alt="([^"]*)" src="([^"]*)" ?/?></p>',
               r'<figure><img alt="\1" src="\2" loading="lazy"><figcaption>\1</figcaption></figure>', corps)
# keys in the shortcuts table
corps = re.sub(r'<td>((?:Ctrl|Shift|Alt|Tab|Space|F\d|←|↑|Home|h l|f|s|d)[^<]*)</td>',
               lambda m: '<td class="touches">' + m.group(1) + '</td>', corps, count=0)

PAGE = """<title>Siby User Guide</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,700&family=Source+Sans+3:ital,wght@0,400;0,600;1,400&family=JetBrains+Mono:wght@500&display=swap">
<style>
/* Layout: one reading column with a sticky contents rail on wide screens;
   colours from Siby's own board (Lichess blue) */
:root {
  --bg: #f5f7fa; --surface: #ffffff; --fg: #1d2430; --muted: #5b6676;
  --line: #d9dfe7; --accent: #2f6fb3; --accent-soft: #e3edf8; --key: #eef1f5;
  --display: "Bricolage Grotesque", "Segoe UI", system-ui, sans-serif;
  --body: "Source Sans 3", "Segoe UI", system-ui, sans-serif;
  --mono: "JetBrains Mono", ui-monospace, Consolas, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #16191e; --surface: #1f242b; --fg: #e4e8ee; --muted: #9aa5b4;
  --line: #313843; --accent: #6fa8e3; --accent-soft: #1f3247; --key: #2a3038; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #16191e; --surface: #1f242b; --fg: #e4e8ee; --muted: #9aa5b4;
  --line: #313843; --accent: #6fa8e3; --accent-soft: #1f3247; --key: #2a3038; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font: 17px/1.6 var(--body);
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.page { max-width: 1180px; margin: 0 auto; padding-block: 40px 80px;
  display: grid; grid-template-columns: 230px minmax(0, 1fr); gap: 48px; }
nav.toc { position: sticky; top: calc(env(safe-area-inset-top, 0px) + 24px); align-self: start;
  font-size: 14.5px; max-height: calc(100vh - 48px); overflow-y: auto; }
nav.toc .marque { font: 700 22px/1.1 var(--display); margin-bottom: 4px; }
nav.toc .sous { color: var(--muted); font-size: 13px; margin-bottom: 18px; }
nav.toc ol { list-style: none; padding: 0; margin: 0; display: grid; gap: 2px; counter-reset: s; }
nav.toc li { counter-increment: s; }
nav.toc a { display: block; padding: 4px 10px; border-radius: 6px; color: var(--muted); text-decoration: none; }
nav.toc a::before { content: counter(s) "  "; font-family: var(--mono); font-size: 11px; color: var(--accent); }
nav.toc a:hover, nav.toc a:focus-visible { background: var(--accent-soft); color: var(--fg); outline: none; }
article { min-width: 0; }
article > h1 { font: 700 clamp(34px, 5vw, 52px)/1.05 var(--display); letter-spacing: -0.02em; margin: 0 0 18px; text-wrap: balance; }
article > p, article li { max-width: 68ch; }
h2 { font: 700 28px/1.2 var(--display); margin: 64px 0 14px; padding-top: 18px; border-top: 1px solid var(--line); text-wrap: balance; scroll-margin-top: 20px; }
h3 { font: 600 19px/1.3 var(--display); margin: 32px 0 8px; scroll-margin-top: 20px; }
a { color: var(--accent); }
hr { display: none; }
article > h2#contents, article > h2#contents + ol { display: none; }
figure { margin: 22px 0 28px; }
figure img { display: block; max-width: 100%; height: auto; border-radius: 8px; border: 1px solid var(--line);
  box-shadow: 0 10px 30px -18px rgba(0,0,0,.45); }
figcaption { color: var(--muted); font-size: 14px; margin-top: 8px; }
em { color: var(--muted); }
p > em:only-child { display: block; border-left: 3px solid var(--accent); padding: 4px 0 4px 14px; color: var(--fg); font-style: normal; background: var(--accent-soft); border-radius: 0 6px 6px 0; }
table { border-collapse: collapse; width: 100%; font-size: 15.5px; margin: 14px 0 22px; }
.tableau { overflow-x: auto; }
th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { font: 600 13px/1.3 var(--body); text-transform: uppercase; letter-spacing: .06em; color: var(--muted); }
td.touches, code { font-family: var(--mono); font-size: 13.5px; }
td.touches { white-space: nowrap; }
code { background: var(--key); padding: 1px 6px; border-radius: 4px; }
@media (max-width: 860px) {
  .page { grid-template-columns: minmax(0, 1fr); gap: 0; padding-block: 24px 60px; }
  nav.toc { position: static; max-height: none; margin-bottom: 8px; }
  body { font-size: 16.5px; }
}
@media (prefers-reduced-motion: no-preference) { nav.toc a { transition: background .15s; } }
</style>
<div class="page">
<nav class="toc" aria-label="Contents">
  <div class="marque">Siby</div>
  <div class="sous">User guide · version 1</div>
  <ol>
__SOMMAIRE__
  </ol>
</nav>
<article>
__CORPS__
</article>
</div>
"""

# contents from the h2 headings
items = re.findall(r'<h2 id="([^"]+)">\d+\. ([^<]+)</h2>', corps)
sommaire = "\n".join(f'    <li><a href="#{i}">{t}</a></li>' for i, t in items)
# wide tables scroll inside their own box
corps = corps.replace("<table>", '<div class="tableau"><table>').replace("</table>", "</table></div>")
(ICI / "USER_GUIDE.html").write_text(PAGE.replace("__SOMMAIRE__", sommaire).replace("__CORPS__", corps), encoding="utf-8")
print("ok", len(items), "sections")
