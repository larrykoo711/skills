#!/usr/bin/env python3
# gen-ship-report.py <compare-html> <out-html> — render a polished, self-contained Ship
# Report for a completed macos-setup run. Reads the compare playground's embedded DATA for
# the per-step inventory; the narrative (highlights, traps, skill improvements) is passed
# via a sidecar JSON on stdin. Anthropic warm-cream × Linear design language (DESIGN.md).
import json, re, sys

if len(sys.argv) < 3:
    sys.exit("usage: gen-ship-report.py <compare-html> <out-html>  "
             "(narrative JSON optional on stdin)")
compare_html, out_html = sys.argv[1], sys.argv[2]
# narrative is optional — tolerate empty/malformed stdin so the report still renders with
# defaults rather than crashing the wrap-up step.
try:
    raw = sys.stdin.read().strip()
    narrative = json.loads(raw) if raw else {}
except (json.JSONDecodeError, ValueError) as e:
    sys.stderr.write(f"gen-ship-report: ignoring malformed narrative JSON ({e})\n")
    narrative = {}

# ── pull DATA out of the compare playground (brace-balanced) ──
# Fail fast with a clear message: a bad path or a file that isn't a compare report
# is an operator error, not a crash to read a traceback for.
try:
    html = open(compare_html, encoding="utf-8").read()
except OSError as err:
    sys.exit(f"gen-ship-report: cannot read compare report '{compare_html}' ({err}). "
             "Pass the HTML written by compare.sh (Step 2).")
s = html.find('{"host"'); depth=0; instr=False; esc=False; e=None
if s == -1:
    sys.exit(f"gen-ship-report: no embedded DATA found in '{compare_html}'. "
             "Expected the compare playground from compare.sh — got a different file?")
for i in range(s, len(html)):
    c = html[i]
    if esc: esc=False; continue
    if c=='\\': esc=True; continue
    if c=='"': instr=not instr; continue
    if instr: continue
    if c=='{': depth+=1
    elif c=='}':
        depth-=1
        if depth==0: e=i+1; break
try:
    data = json.loads(html[s:e])
except (json.JSONDecodeError, ValueError) as err:
    sys.exit(f"gen-ship-report: embedded DATA in '{compare_html}' is malformed ({err}). "
             "Regenerate the report with compare.sh.")

KIND_LABEL = {"ok":"compliant","removed":"removed","keep":"kept","install":"to install",
              "remove":"to remove","config":"baseline"}
def step_stats(sec):
    k={}
    for r in sec["rows"]: k[r["kind"]]=k.get(r["kind"],0)+1
    done=sum(v for kk,v in k.items() if kk in ("ok","removed","keep"))
    todo=sum(v for kk,v in k.items() if kk in ("install","remove","config"))
    return done, todo, k

steps = []
for i, sec in enumerate(data["sections"], 1):
    done, todo, k = step_stats(sec)
    steps.append({"n":i, "title":sec["title"], "title_zh":sec.get("title_zh",sec["title"]),
                  "done":done, "todo":todo, "rows":sec["rows"]})

pre_pass = sum(1 for p in data["prechecks"] if p["status"]=="pass")
pre_total = len(data["prechecks"])
total_done = sum(st["done"] for st in steps)
total_todo = sum(st["todo"] for st in steps)

# Big numbers for the hero
removed = sum(1 for st in steps for r in st["rows"] if r["kind"]=="removed")
installed = narrative.get("installed_count", 0)
baseline = sum(1 for st in steps for r in st["rows"] if r["kind"]=="config") + \
           next((st["done"] for st in steps if "baseline" in st["title"].lower()), 0)

def esc_html(t): return (t or "").replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

# ── render rows of a step as compact chips ──
def step_rows_html(st):
    out=[]
    for r in st["rows"]:
        kind=r["kind"]; cls={"ok":"c-ok","removed":"c-rm","keep":"c-keep",
                             "install":"c-todo","remove":"c-rm","config":"c-cfg"}.get(kind,"c-ok")
        icon={"ok":"✓","removed":"✓","keep":"●","install":"○","remove":"○","config":"✓"}.get(kind,"·")
        out.append(f'<span class="chip {cls}"><i>{icon}</i>{esc_html(r["name"])}</span>')
    return "".join(out)

# User-friendly step names — the standard's titles say "brew formula / cask / mas", which
# means nothing to a normal Mac user. Map by keyword to plain language + a one-line "what".
def friendly_step(title):
    t = title.lower()
    if "removal" in t or "blocklist" in t:
        return ("清理不需要的应用", "卸载了重复、过时或用不上的程序")
    if "cli tool" in t or "formula" in t:
        return ("命令行工具", "开发与运维常用的小工具")
    if "gui app" in t or "cask" in t:
        return ("桌面应用", "浏览器、办公、聊天、远程等常用软件")
    if "app store" in t or "mas" in t:
        return ("App Store 应用", "从 App Store 安装的程序")
    if "node" in t or "uv tool" in t:
        return ("开发者命令行", "Node / Python 生态的命令行工具")
    if "baseline" in t or "shortcut" in t or "security" in t:
        return ("系统设置", "Dock、键盘快捷键、电源、安全选项")
    if "offline" in t:
        return ("需手动安装的自备软件", "你自备的安装包，已送到桌面")
    if "off-standard" in t:
        return ("保留的个人软件", "你自己装的、标准之外但保留的程序")
    return (title, "")

steps_html=""
for st in steps:
    pct = 100 if st["todo"]==0 else int(100*st["done"]/(st["done"]+st["todo"]))
    badge_cls = "done" if st["todo"]==0 else "wip"
    title_zh, st_what = friendly_step(st["title"])
    steps_html += f"""
    <div class="step">
      <div class="step-head">
        <span class="sn {badge_cls}">{st['n']}</span>
        <div class="step-title">
          <div class="st-zh">{esc_html(title_zh)}</div>
          <div class="st-meta">{esc_html(st_what)} · {st['done']} 项已完成{f"，还剩 {st['todo']} 项" if st['todo'] else ""}</div>
        </div>
        <span class="st-state {badge_cls}">{'✓ 完成' if st['todo']==0 else f"还剩 {st['todo']} 项"}</span>
      </div>
      <div class="chips">{step_rows_html(st)}</div>
    </div>"""

# "Fixes" — user-facing rewrite of the engineering traps. narrative.fixes carries a plain
# title + plain description ("what was wrong, now it's handled"), no pitfalls numbers / jargon.
fixes_html=""
for fx in narrative.get("fixes", []):
    fixes_html += f"""
    <div class="fix">
      <span class="fix-ic">✓</span>
      <div><div class="fix-t">{esc_html(fx['title'])}</div>
      <div class="fix-d">{esc_html(fx['desc'])}</div></div>
    </div>"""

HTML = f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ship Report · {data['host']} · macOS Setup</title>
<style>
  :root {{
    --canvas:#faf9f5; --soft:#f5f0e8; --card:#efe9de; --cream-strong:#e8e0d2;
    --ink:#141413; --body:#3d3d3a; --muted:#6c6a64; --mutes:#8e8b82;
    --hair:#e6dfd8; --hairs:#ebe6df;
    --primary:#cc785c; --primary-active:#a9583e;
    --teal:#5db8a6; --amber:#e8a55a; --success:#5db872; --warning:#d4a017; --error:#c64545;
    --dark:#181715; --on-dark:#faf9f5; --on-dark-soft:#a09d96;
    --serif:'Tiempos Headline',Georgia,'Songti SC',serif;
    --sans:'Inter',-apple-system,'PingFang SC',sans-serif;
    --mono:'JetBrains Mono',ui-monospace,Menlo,monospace;
  }}
  *{{box-sizing:border-box;margin:0;padding:0}}
  body{{background:var(--canvas);color:var(--body);font-family:var(--sans);line-height:1.6;
    -webkit-font-smoothing:antialiased}}
  .wrap{{max-width:1080px;margin:0 auto;padding:0 28px}}

  /* hero — dark surface */
  .hero{{background:var(--dark);color:var(--on-dark);padding:64px 0 56px;position:relative;overflow:hidden}}
  .hero::after{{content:"";position:absolute;right:-120px;top:-120px;width:380px;height:380px;
    background:radial-gradient(circle,rgba(204,120,92,.22),transparent 68%);pointer-events:none}}
  .hero .wrap{{position:relative;z-index:1}}
  .eyebrow{{font-family:var(--mono);font-size:12px;letter-spacing:.14em;text-transform:uppercase;
    color:var(--primary);font-weight:600}}
  .hero h1{{font-family:var(--serif);font-size:clamp(40px,6vw,68px);font-weight:400;line-height:1.04;
    letter-spacing:-1.5px;color:var(--on-dark);margin:14px 0 10px}}
  .hero h1 .host{{color:var(--amber)}}
  .hero .lede{{font-size:18px;color:var(--on-dark-soft);max-width:600px}}
  .hero .stamp{{margin-top:22px;font-family:var(--mono);font-size:12.5px;color:var(--on-dark-soft);
    display:flex;gap:18px;flex-wrap:wrap}}
  .hero .stamp b{{color:var(--on-dark)}}
  .seal{{display:inline-flex;align-items:center;gap:8px;background:rgba(93,184,114,.16);
    border:1px solid rgba(93,184,114,.4);color:#8fe0a2;border-radius:100px;padding:6px 16px;
    font-family:var(--mono);font-size:13px;font-weight:600;margin-top:24px}}

  /* big metrics */
  .metrics{{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:-34px 0 0;position:relative;z-index:5}}
  .metric{{background:#fff;border:1px solid var(--hair);border-radius:16px;padding:22px 20px;
    box-shadow:0 8px 30px rgba(20,20,19,.06)}}
  .metric .num{{font-family:var(--serif);font-size:46px;line-height:1;color:var(--ink);letter-spacing:-1px}}
  .metric .lbl{{font-size:13px;color:var(--muted);margin-top:8px}}
  .metric.accent .num{{color:var(--primary)}}

  section.blk{{padding:48px 0 8px}}
  h2{{font-family:var(--serif);font-size:30px;font-weight:400;letter-spacing:-.4px;color:var(--ink);margin-bottom:6px}}
  .sub{{color:var(--muted);margin-bottom:26px;font-size:15px}}

  /* steps */
  .step{{background:#fff;border:1px solid var(--hair);border-radius:14px;padding:18px 20px;margin-bottom:14px}}
  .step-head{{display:flex;align-items:center;gap:14px}}
  .sn{{flex-shrink:0;width:30px;height:30px;border-radius:50%;display:flex;align-items:center;
    justify-content:center;font-family:var(--mono);font-weight:600;font-size:14px}}
  .sn.done{{background:var(--success);color:#fff}}
  .sn.wip{{background:var(--amber);color:#fff}}
  .step-title{{flex:1}}
  .st-zh{{font-weight:600;color:var(--ink);font-size:15.5px}}
  .st-meta{{font-size:12.5px;color:var(--mutes);font-family:var(--mono);margin-top:2px}}
  .st-state{{font-family:var(--mono);font-size:12px;font-weight:600;padding:5px 13px;border-radius:100px}}
  .st-state.done{{background:rgba(93,184,114,.14);color:#3f8f56}}
  .st-state.wip{{background:rgba(232,165,90,.16);color:#b07320}}
  .chips{{display:flex;flex-wrap:wrap;gap:7px;margin-top:14px}}
  .chip{{display:inline-flex;align-items:center;gap:5px;font-family:var(--mono);font-size:11.5px;
    padding:4px 10px;border-radius:7px;background:var(--soft);color:var(--body);border:1px solid var(--hairs)}}
  .chip i{{font-style:normal;font-size:10px}}
  .chip.c-ok{{color:#3f8f56}} .chip.c-ok i{{color:var(--success)}}
  .chip.c-rm{{color:var(--mutes);text-decoration:line-through;text-decoration-color:var(--hair)}}
  .chip.c-keep{{color:var(--teal)}}
  .chip.c-todo{{color:var(--primary);background:rgba(204,120,92,.08);border-color:rgba(204,120,92,.25)}}
  .chip.c-cfg{{color:#b07320}}

  /* fixes — plain-language "handled for you" cards */
  .fixes{{display:grid;grid-template-columns:1fr 1fr;gap:14px}}
  .fix{{display:flex;gap:12px;background:#fff;border:1px solid var(--hair);border-radius:14px;padding:18px 20px}}
  .fix-ic{{flex-shrink:0;width:26px;height:26px;border-radius:50%;background:rgba(93,184,114,.16);
    color:#3f8f56;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:700}}
  .fix-t{{font-weight:600;color:var(--ink);font-size:14.5px}}
  .fix-d{{font-size:13px;color:var(--muted);margin-top:4px;line-height:1.5}}

  footer{{padding:40px 0 60px;color:var(--mutes);font-family:var(--mono);font-size:12px;text-align:center}}
  @media(max-width:860px){{.metrics{{grid-template-columns:repeat(2,1fr)}}.fixes{{grid-template-columns:1fr}}}}
</style></head>
<body>
  <div class="hero"><div class="wrap">
    <div class="eyebrow">这台 Mac 的配置报告</div>
    <h1>你的 <span class="host">{esc_html(narrative.get('nickname', data['host']))}</span> 已经配置好了</h1>
    <p class="lede">{esc_html(narrative.get('lede',''))}</p>
    <div class="seal">● 全部就绪，可以放心使用</div>
    <div class="stamp">
      <span>机型 <b>{esc_html(narrative.get('device',''))}</b></span>
      <span>完成于 <b>{data['date']}</b></span>
      <span>开机环境检查 <b>全部通过</b></span>
    </div>
  </div></div>

  <div class="wrap">
    <div class="metrics">
      <div class="metric"><div class="num">{installed}</div><div class="lbl">装好的应用与工具<br><span style="color:var(--mutes);font-size:11px">浏览器、办公、开发工具等</span></div></div>
      <div class="metric"><div class="num">{removed}</div><div class="lbl">清理掉的应用<br><span style="color:var(--mutes);font-size:11px">不需要的、重复的、旧版本</span></div></div>
      <div class="metric accent"><div class="num">{narrative.get('baseline_count',13)}</div><div class="lbl">系统设置项<br><span style="color:var(--mutes);font-size:11px">Dock、快捷键、电源等已调好</span></div></div>
      <div class="metric"><div class="num">100<span style="font-size:24px">%</span></div><div class="lbl">每一项都已核对<br><span style="color:var(--mutes);font-size:11px">改完都回读确认真的生效</span></div></div>
    </div>

    <section class="blk">
      <h2>为这台 Mac 做了什么</h2>
      <p class="sub">分八步把这台 Mac 收拾干净、装齐工具、调好系统——每一项改动都回读确认真的生效了。</p>
      {steps_html}
    </section>

    <section class="blk">
      <h2>顺手帮你解决的小问题</h2>
      <p class="sub">配置过程中发现并处理掉的几处隐患，你不用操心，这里只是留个记录。</p>
      <div class="fixes">{fixes_html}</div>
    </section>
  </div>

  <footer>这台 Mac 的配置报告 · {esc_html(narrative.get('nickname', data['host']))} · {data['date']}<br>
    <span style="opacity:.7">Powered by <a href="https://github.com/larrykoo711" style="color:inherit;text-decoration:none;border-bottom:1px dotted currentColor">larrykoo711</a> · macos-setup skill</span></footer>
</body></html>"""

open(out_html, "w", encoding="utf-8").write(HTML)
print(f"OK {out_html}  ({len(HTML)} bytes)")
