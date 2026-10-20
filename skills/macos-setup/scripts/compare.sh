#!/usr/bin/env bash
# compare.sh — Step 2: device vs standard → interactive playground report (read-only).
# Writes ~/Desktop/macos-setup-playground-<host>.html, opens it in the default
# browser, and asks the user (by voice) to annotate it.
# Row kinds:
#   install — in the standard, missing here (default: approve)
#   remove  — blocklisted, present here   (default: approve; executed one-by-one)
#   ok      — compliant
#   keep    — off-standard, present here  (default: keep; user may choose removal)
#   config  — settings/shortcuts/security drift (default: approve baseline write)
# Env overrides: MACOS_SETUP_OUT=<path>   MACOS_SETUP_SILENT=1 (no browser, no voice)
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
# Raw collection goes under the run's .task raw/ when MACOS_SETUP_TASK_DIR is set (seeded
# by task-init.sh), else /tmp. The report still lands on the Desktop for the user; it's
# also archived into the task's artifacts/ at the end of this script.
RAW="${MACOS_SETUP_TASK_DIR:+$MACOS_SETUP_TASK_DIR/raw}"; RAW="${RAW:-/tmp}"
CUR="$RAW/macos-setup-collect-$HOST.tsv"
# Default output: the target machine's Desktop, where the user will see it first.
OUT="${MACOS_SETUP_OUT:-$HOME/Desktop/macos-setup-playground-$HOST.html}"
# Execution ledger: what THIS run actually did (cleanup/pipeline append to it). compare
# reads it so a blocklist item that's gone can be told apart — `removed ✓` (we removed it
# this run) vs simply never installed (not our doing, not shown). Empty/absent on a fresh
# run, so the report stays a pure snapshot until something executes.
LEDGER="${MACOS_SETUP_LEDGER:-$RAW/macos-setup-executed-$HOST.tsv}"

# Prerequisites feed the report's first module; unmet items gate all interaction.
PRECHK="$RAW/macos-setup-precheck-$HOST.tsv"
PRECHECK_TSV="$PRECHK" bash "$SCRIPT_DIR/precheck.sh" || true

# A blank Mac has no real python3: /usr/bin/python3 is a CLT stub that pops an install
# dialog and fails — the report would silently not exist. Prerequisites first.
if ! xcode-select -p >/dev/null 2>&1; then
  fail "blank Mac: Xcode CLT missing, so the report cannot be generated (python3 is a stub)."
  fail "install the prerequisites first:  pipeline.sh --prereqs-only   (CLT + Homebrew, nothing else)"
  exit 1
fi

bash "$SCRIPT_DIR/collect.sh" "$CUR"

rm -f "$OUT"     # a report left by an earlier run must never pass for this one
/usr/bin/python3 - "$SKILL_DIR" "$CUR" "$OUT" "$HOST" "$PRECHK" "$LEDGER" <<'PYEOF'
import json, re, sys, datetime, pathlib, os, glob
skill, curf, outf, host, prechk, ledgerf = sys.argv[1:7]
skill = pathlib.Path(skill)

# ── execution ledger: {(action, type, short_name)} this run actually performed ──
# Lines: "<action>\t<type>\t<name>" e.g. "removed\tformula\tautojump". Used to mark a
# now-absent blocklist item as removed-this-run (vs never-installed, which isn't shown).
executed = set()
try:
    for line in open(ledgerf, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3:
            executed.add((parts[0], parts[1], parts[2].split("/")[-1]))
except FileNotFoundError:
    pass
def was_removed(t, n): return ("removed", t, n.split("/")[-1]) in executed

# ── prerequisite results ──
prechecks = []
try:
    for line in open(prechk, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2:
            prechecks.append({"status": parts[0], "desc": parts[1],
                              "desc_zh": parts[2] if len(parts) > 2 and parts[2] else parts[1]})
except FileNotFoundError:
    pass

# ── current state ──
cur = {}   # category -> set(names)
cfg = {}   # "category:key" -> value (default/security/power/hotkey)
for line in open(curf, encoding="utf-8"):
    line = line.rstrip("\n")
    if "\t" not in line: continue
    t, n = line.split("\t", 1)
    if t in ("default", "security", "power", "hotkey"):
        k, _, v = n.partition("="); cfg[f"{t}:{k}"] = v
    else:
        cur.setdefault(t, set()).add(n)

def has(t, n): return n in cur.get(t, set())
def short(name): return name.split("/")[-1]
# Homebrew is renaming some casks to a `-app` suffix (tailscale → tailscale-app); the
# standard still names the short form, but `brew list --cask` reports the installed
# (suffixed) name. Match either so a renamed-but-present cask isn't judged missing — which
# would re-propose installing it forever and fight pitfalls #4's "adopt-only, never reinstall".
def has_cask(n): return n in cur.get("cask", set()) or (n + "-app") in cur.get("cask", set())

# ── the standard ──
std_brew, std_cask, std_mas = [], [], []
for line in open(skill / "standard/Brewfile.standard", encoding="utf-8"):
    line = line.strip()
    if m := re.match(r'^brew "([^"]+)"', line):  std_brew.append(m.group(1))
    if m := re.match(r'^cask "([^"]+)"', line):  std_cask.append(m.group(1))
    if m := re.match(r'^mas "([^"]+)", id: (\d+)', line): std_mas.append((m.group(1), m.group(2)))

block = []  # (type, name)
for line in open(skill / "standard/blocklist.txt", encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#") or "\t" not in line: continue
    block.append(tuple(line.split("\t", 1)))

def read_tsv(p):
    return [l.split("\t") for l in (skill / p).read_text(encoding="utf-8").splitlines()
            if l and not l.startswith("#")]
node_g  = read_tsv("standard/node-globals.txt")
uv_t    = read_tsv("standard/uv-tools.txt")
hotkeys = [(p[0], p[1], p[2] if len(p) > 2 else "", p[3] if len(p) > 3 else "")
           for p in read_tsv("standard/hotkeys.tsv")]

# ── diff → sections (every row carries `id`: the token used in the exclude file).
#    Titles and config names ship in both languages; the report picks at render time.
sections = []
def section(title, title_zh, rows):
    if rows: sections.append({"title": title, "title_zh": title_zh, "rows": rows})

# Removals FIRST — and the report tells the user to do them before anything installs.
# Why order matters here, not just visually: installing while blocklisted tools are still
# present risks the new setup picking up a dependency on something about to be deleted
# (a shell plugin, a CLI another formula shims to, an app a cask links against), leaving a
# half-broken state once removal runs. Clear the deck, then converge onto a clean base.
#
# Show the FULL blocklist with a terminal state per row — present → `remove` (to do), gone
# → `removed` (✅ done). A blocklisted item that's no longer on the machine isn't dropped
# from the report: that would erase the progress trail, leaving "never had it" and "removed
# it this run" indistinguishable. Mirrors how install rows persist as `ok` once satisfied.
rows = []
for t, n in block:
    present = has(t, n) or (t == "formula" and has(t, short(n)))
    if present:
        cmd = {"formula": f"brew uninstall {n}", "cask": f"brew uninstall --cask {n}",
               "app": f"remove /Applications/{n}.app", "pnpm-g": f"pnpm remove -g {n}",
               "uv-tool": f"uv tool uninstall {n}", "local-bin": f"remove ~/.local/bin/{n}"}[t]
        rows.append({"name": n, "id": short(n), "type": t, "current": "present",
                     "action": cmd, "kind": "remove"})
    elif was_removed(t, n):
        # gone AND we removed it this run → keep as a ✓ progress trail
        rows.append({"name": n, "id": short(n), "type": t, "current": "✓ removed",
                     "action": "removed this run", "kind": "removed"})
    # else: gone and we didn't touch it → never installed here, not our result, skip
section("⛔ Removals — do these FIRST: rejected by the standard, present on this device",
        "⛔ 优先卸载 — 请先做：标准明确不要、本机存在（先清理再安装，避免装上对将卸载项的依赖）", rows)

rows = []
for f in std_brew:
    okk = has("formula", f) or has("formula", short(f))
    rows.append({"name": short(f), "id": short(f), "type": "formula",
                 "current": "✓ installed" if okk else "missing",
                 "action": "compliant" if okk else f"brew install {f}",
                 "kind": "ok" if okk else "install"})
section("CLI tools — brew formulas (standard)", "CLI 工具 — brew formula（标准）", rows)

rows = []
for c in std_cask:
    okk = has_cask(c)
    rows.append({"name": c, "id": c, "type": "cask",
                 "current": "✓ cask" if okk else "missing",
                 "action": "compliant" if okk else f"brew install --cask --adopt {c}",
                 "kind": "ok" if okk else "install"})
section("GUI apps — brew casks (standard)", "GUI 应用 — brew cask（标准）", rows)

rows = []
for m, mid in std_mas:
    # Match by mas id (stable) first — the display name is localized (on a non-English
    # machine the App Store shows the translated app name, never the standard's "Pages"),
    # so name matching alone always misses. Fall back to name / .app presence. (pitfalls #23)
    okk = has("mas-id", mid) or has("mas", m) or has("app", m)
    rows.append({"name": m, "id": m, "type": "mas",
                 "current": "✓ installed" if okk else "missing",
                 "action": "compliant" if okk else f"mas install {mid} (App Store sign-in required)",
                 "kind": "ok" if okk else "install"})
section("App Store apps — mas (standard)", "App Store 应用 — mas（标准）", rows)

rows = []
for binname, pkg in node_g:
    # collect now emits the shim/bin name (ground truth for "command runs"); match on it.
    # Keep pkg-name + local-bin as fallbacks for older snapshots. (pitfalls #25)
    okk = has("pnpm-g", binname) or has("pnpm-g", pkg) or has("local-bin", binname)
    rows.append({"name": binname, "id": binname, "type": "pnpm -g",
                 "current": "✓" if okk else "missing",
                 "action": "compliant" if okk else f"pnpm add -g {pkg}",
                 "kind": "ok" if okk else "install"})
for binname, pkg in uv_t:
    okk = has("uv-tool", pkg) or has("local-bin", binname)
    rows.append({"name": binname, "id": binname, "type": "uv tool",
                 "current": "✓" if okk else "missing",
                 "action": "compliant" if okk else f"uv tool install {pkg}",
                 "kind": "ok" if okk else "install"})
section("Node globals & uv tools (standard)", "Node 全局 & uv 工具（标准）", rows)

# settings / shortcuts / security baseline (mirrors collect.sh and verify.sh)
std_cfg = [
    ("default:NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically", "1", "Appearance: Auto (light/dark)", "外观：自动（浅/深色）"),
    ("default:NSGlobalDomain.KeyRepeat", "2", "Key repeat: fastest", "按键重复：最快"),
    ("default:NSGlobalDomain.InitialKeyRepeat", "15", "Key repeat delay: shortest", "重复前延迟：最短"),
    ("default:NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled", "0", "Auto spelling correction: off", "自动拼写纠正：关"),
    ("default:NSGlobalDomain.NSAutomaticCapitalizationEnabled", "0", "Auto capitalization: off", "自动首字母大写：关"),
    ("default:com.apple.AppleMultitouchTrackpad.Clicking", "1", "Trackpad: tap to click", "触控板：轻点点按"),
    ("default:com.apple.AppleMultitouchTrackpad.TrackpadThreeFingerDrag", "1", "Trackpad: three-finger drag", "触控板：三指拖移"),
    ("default:com.apple.dock.magnification", "1", "Dock: magnification on", "Dock：放大开启"),
    ("default:com.apple.dock.autohide", "0", "Dock: always visible", "Dock：常驻显示"),
    ("default:com.apple.dock.tilesize", "48", "Dock: tile size 48", "Dock：图标尺寸 48"),
    ("default:com.apple.dock.show-recents", "0", "Dock: hide recent apps", "Dock：隐藏最近使用"),
    ("power:ac-sleep", "0", "On AC power: never sleep", "接电源：永不休眠"),
    ("security:firewall", "on", "Application Firewall", "应用防火墙"),
    ("security:sip", "on", "System Integrity Protection", "系统完整性保护 (SIP)"),
    ("security:filevault", "on", "FileVault", "FileVault 磁盘加密"),
] + [(f"hotkey:{hid}", want, f"⌨ {d_en}", f"⌨ {d_zh or d_en}") for hid, want, d_en, d_zh in hotkeys]

rows = []
for token, want, desc, desc_zh in std_cfg:
    got = cfg.get(token, "<not collected>")
    okk = got == want
    rows.append({"name": desc, "name_zh": desc_zh, "id": token, "type": token.split(":")[0],
                 "current": got,
                 "action": "compliant" if okk else f"apply baseline → {want} (write + read back)",
                 "kind": "ok" if okk else "config"})
section("Settings · shortcuts · security baseline", "系统设置 · 快捷键 · 安全基线", rows)

# offline-apps — bring-your-own app installers staged to the Desktop, installed by hand.
# Detect presence by scanning /Applications (fuzzy: app name or its first word).
installed_apps = [os.path.basename(p)[:-4].lower() for p in glob.glob("/Applications/*.app")]
def app_present(name):
    key = name.split()[0].lower()
    return any(a == name.lower() or a.startswith(key) for a in installed_apps)
rows = []
for p in read_tsv("standard/offline-apps.tsv"):
    if len(p) < 3: continue
    fn, app, ver = p[0], p[1], p[2]
    okk = app_present(app)
    rows.append({"name": f"{app} {ver}", "name_zh": f"{app} {ver}", "id": short(fn),
                 "type": "offline", "current": "✓ installed" if okk else "not installed",
                 "action": "compliant" if okk else "staged to Desktop → install by hand (guide included)",
                 "kind": "ok" if okk else "install"})
section("Offline installers — bring-your-own apps staged to the Desktop",
        "离线安装包 — 自备 App 送达桌面手动装", rows)

# off-standard: present here, mentioned by neither the standard nor the blocklist.
# A blocklist row already has a verdict (→ remove); it must NOT also surface as a keep
# candidate. Blocklist/collect names are full tap paths (danielfoehrkn/switch/switch), so
# match BOTH the full name and its short last segment — short-only let tap-pathed entries
# slip through and appear in two sections at once. Also fold in std_cask short names: a
# formula that shares a cask's name (e.g. `tailscale` formula vs `cask "tailscale"`) is a
# type mismatch, not a genuine off-standard extra — keep it out of the keep list.
def name_forms(n): return {n, short(n)}
known_f = ({short(x) for x in std_brew} | {short(c) for c in std_cask}
           | {form for t, n in block if t == "formula" for form in name_forms(n)})
known_c = (set(std_cask) | {short(c) for c in std_cask}
           | {form for t, n in block if t == "cask" for form in name_forms(n)})
rows = []
# Off-standard EXTRAS use leaves (top-level), not the full formula list — otherwise every
# dependency pulled in by a standard tool would show up here as an "extra to keep".
# leaves emit full tap paths (steipete/tap/peekaboo) while known_f holds short names, so
# compare on the short segment; show the full leaf name for clarity.
for f in sorted(x for x in cur.get("formula-leaf", set()) if short(x) not in known_f):
    rows.append({"name": f, "id": short(f), "type": "formula", "current": "✓",
                 "action": "keep (off-standard)", "kind": "keep"})
# A cask is "known" if its name — or its de-suffixed `-app` form (see has_cask) — is in
# known_c, so a renamed standard cask (tailscale-app) isn't mistaken for an off-standard extra.
def cask_known(c): return c in known_c or (c.endswith("-app") and c[:-4] in known_c)
for c in sorted(x for x in cur.get("cask", set()) if not cask_known(x)):
    rows.append({"name": c, "id": c, "type": "cask", "current": "✓",
                 "action": "keep (off-standard)", "kind": "keep"})
# Off-standard items removed THIS run leave a `removed ✓` trail here too (same principle as
# the blocklist section, pitfalls #18) — an off-standard extra the user chose to drop must
# not just vanish from the report. Pull from the ledger anything removed that isn't a
# blocklist entry (those are shown in Step 1) and isn't still present.
block_short = {short(n) for t, n in block}
present_now = cur.get("formula", set()) | {short(x) for x in cur.get("formula-leaf", set())} | cur.get("cask", set())
for action, t, nm in sorted(executed):
    if action != "removed" or short(nm) in block_short or short(nm) in present_now:
        continue
    rows.append({"name": nm, "id": short(nm), "type": t, "current": "✓ removed",
                 "action": "removed this run (off-standard)", "kind": "removed"})
section("Off-standard — present here, not in the standard (default: keep)",
        "标准外 — 本机有、标准没有（默认保留）", rows)

data = {"host": host, "date": str(datetime.date.today()), "prechecks": prechecks, "sections": sections}

tpl = (skill / "templates/setup-playground.html").read_text(encoding="utf-8")
out = tpl.replace("__SETUP_DATA__", json.dumps(data, ensure_ascii=False))
pathlib.Path(outf).write_text(out, encoding="utf-8")
todo = sum(1 for s in sections for r in s["rows"] if r["kind"] in ("install", "remove", "config"))
print(f"OK {outf}  pending {todo}")
PYEOF
py_rc=$?
[ "$py_rc" -eq 0 ] && [ -s "$OUT" ] || { fail "report generation failed (python exit $py_rc, file: $OUT)"; exit 1; }

# Archive the report into the run's task dir (beside raw/), if one is active.
[ -n "${MACOS_SETUP_TASK_DIR:-}" ] && [ -d "$MACOS_SETUP_TASK_DIR/artifacts" ] \
  && cp "$OUT" "$MACOS_SETUP_TASK_DIR/artifacts/compare-playground.html" 2>/dev/null

# Quiet mode for tests / remote orchestration: skip browser + voice.
[ "${MACOS_SETUP_SILENT:-0}" = "1" ] && exit 0

# Open in the default browser, then request the user's help by voice.
# Follow-up reminders are driven by the agent layer: poll for the pasted order
# sheet, call assist_remind_or_silent on each empty poll (3 max, then silence).
open "$OUT" 2>/dev/null || true
rm -f "$ASSIST_COUNT_FILE"
UNMET="$(awk -F'\t' '$1=="block"||$1=="manual"{n++} END{print n+0}' "$PRECHK" 2>/dev/null)"
if [ "${UNMET:-0}" -gt 0 ]; then
  assist_notify report_gated "$UNMET"
else
  assist_notify report_ready
fi
