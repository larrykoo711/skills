#!/usr/bin/env bash
# lib/idempotent.sh — shared helpers, sourced by every macos-setup script.
# Contract: every operation is re-entrant; every write is read back and verified;
# every failure becomes a finding — nothing fails silently.
# NOTE: the print helper is `msg`, never `say` — a `say()` function would shadow
# /usr/bin/say and silently kill voice notifications.

set -u

# ── output ──
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; YLW=$'\033[0;33m'; NC=$'\033[0m'
msg()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$NC" "$*"; }
warn() { printf '%s⚠%s %s\n' "$YLW" "$NC" "$*"; }
fail() { printf '%s✗%s %s\n' "$RED" "$NC" "$*"; }

# ── findings (consumed by the convergence checklist, templates/setup-report.md) ──
# Findings land in the run's task dir (raw/) when MACOS_SETUP_TASK_DIR is set (seeded by
# task-init.sh), else /tmp — keeping each run's findings beside its other artifacts.
FINDINGS_FILE="${FINDINGS_FILE:-${MACOS_SETUP_TASK_DIR:+$MACOS_SETUP_TASK_DIR/raw/findings.txt}}"
FINDINGS_FILE="${FINDINGS_FILE:-/tmp/macos-setup-findings.txt}"
report_ok()      { ok "$1";   printf -- '- ✅ %s\n' "$1" >> "$FINDINGS_FILE"; }
report_finding() { fail "$1"; printf -- '- ❌ %s\n' "$1" >> "$FINDINGS_FILE"; }

# ── idempotency primitives ──
have() { command -v "$1" >/dev/null 2>&1; }

# User rejections from the playground order sheet (one token per line).
# Packages use bare names; settings use namespaced tokens:
#   default:<domain>.<key>   hotkey:<id>   security:<name>   power:ac-sleep
# Set MACOS_SETUP_EXCLUDE to the exclude file path (pipeline.sh exports it).
cfg_excluded() {
  [ -n "${MACOS_SETUP_EXCLUDE:-}" ] && [ -f "$MACOS_SETUP_EXCLUDE" ] \
    && grep -qxF "$1" "$MACOS_SETUP_EXCLUDE"
}

# Dock apps (standard/dock-apps.txt) — shared by d03 (write) and verify (read-only).
# Compared by app name (fully URL-decoded): Safari reads back from its Cryptex path, labels are
# localized. The target order = the standard's apps that are installed, in standard order, then
# every other app already pinned, in its current order — converging never unpins anything
# (removals are never automatic).
dock_current() {
  dockutil --list 2>/dev/null | awk -F'\t' '$2 ~ /\.app\/?$/ {print $2}' \
    | /usr/bin/python3 -c 'import sys,urllib.parse,os
for l in sys.stdin: print(os.path.basename(urllib.parse.unquote(l.strip()).rstrip("/"))[:-4])'
}
dock_standard_present() {
  grep -vE '^\s*(#|$)' "$(dirname "${BASH_SOURCE[0]}")/../../standard/dock-apps.txt" \
    | while IFS= read -r app; do [ -d "$app" ] && basename "$app" .app; done
}
dock_expected() {
  local std; std="$(dock_standard_present)"
  printf '%s\n' "$std"
  dock_current | while IFS= read -r a; do printf '%s\n' "$std" | grep -qxF "$a" || printf '%s\n' "$a"; done
}

# Machine profile (set once by `pipeline.sh --profile <name>`, read by every later run).
PROFILE_FILE="$HOME/.config/macos-setup/profile"
current_profile() { [ -f "$PROFILE_FILE" ] && head -1 "$PROFILE_FILE" || true; }

# Xcode Command Line Tools without the GUI dialog: the in-progress marker makes
# softwareupdate list CLT, then install it by label. Needs (passwordless) sudo.
ensure_clt() {
  xcode-select -p >/dev/null 2>&1 && { ok "Xcode CLT present"; return 0; }
  sudo -n true 2>/dev/null || { report_finding "Xcode CLT missing and no passwordless sudo — install it from the dialog (xcode-select --install)"; return 1; }
  msg "Installing Xcode Command Line Tools (headless)…"
  local marker=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress label
  touch "$marker"
  label="$(softwareupdate -l 2>/dev/null | sed -n 's/^\* Label: \(Command Line Tools.*\)$/\1/p' | sort -V | tail -1)"
  [ -n "$label" ] && sudo softwareupdate -i "$label" --verbose >/dev/null 2>&1
  rm -f "$marker"
  xcode-select -p >/dev/null 2>&1 && report_ok "Xcode CLT installed (${label})" \
    || { report_finding "Xcode CLT headless install failed (label: ${label:-not found}) — xcode-select --install"; return 1; }
}

ensure_brew() {
  if have brew; then ok "Homebrew present ($(brew --version | head -1))"; return 0; fi
  msg "Installing Homebrew…"
  # NONINTERACTIVE: no "press RETURN" prompt; sudo must already work (agent-bootstrap).
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    report_finding "Homebrew install failed"; return 1; }
  # Apple Silicon and Intel prefixes
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
}

# write_verify <domain> <key> <type> <value> [expected-read-back]
# `defaults write` can fail SILENTLY (no Full Disk Access → the write lands in a
# legacy path and never takes effect). Always read back. See pitfalls #1.
write_verify() {
  local domain="$1" key="$2" type="$3" value="$4" expect="${5:-$4}"
  if cfg_excluded "default:$domain.$key"; then
    msg "  skip $domain $key (rejected by user)"; return 0
  fi
  defaults write "$domain" "$key" "$type" "$value" 2>/dev/null
  local got
  got="$(defaults read "$domain" "$key" 2>/dev/null)"
  if [ "$got" = "$expect" ]; then
    report_ok "$domain $key = $got"
  else
    report_finding "$domain $key expected $expect, got ${got:-<empty>} (silent failure? grant this terminal Full Disk Access, then re-run)"
  fi
}

# set_hotkey <id> <true|false> — toggle one symbolic hotkey.
# Writes must go through `defaults` (cfprefsd); editing the plist directly gets
# overwritten by the preferences cache. Run activateSettings -u afterwards.
set_hotkey() {
  local id="$1" enabled="$2" flag="<false/>"
  if cfg_excluded "hotkey:$id"; then msg "  skip hotkey $id (rejected by user)"; return 0; fi
  [ "$enabled" = "true" ] && flag="<true/>"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$id" \
    "<dict><key>enabled</key>${flag}</dict>" 2>/dev/null
}

# verify_hotkey <id> <true|false> <label> — read back one hotkey state.
# Read via export + plutil JSON: modifier masks are unreadable by eye (pitfalls #6).
verify_hotkey() {
  local id="$1" expect="$2" desc="$3" got
  got="$(defaults export com.apple.symbolichotkeys - 2>/dev/null \
    | plutil -convert json -o - - 2>/dev/null \
    | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin)['AppleSymbolicHotKeys'].get('$id',{}); print(str(d.get('enabled','absent')).lower())" 2>/dev/null)"
  if [ "$got" = "$expect" ]; then
    report_ok "hotkey $id ($desc) enabled=$got"
  else
    report_finding "hotkey $id ($desc) expected $expect, got ${got:-unreadable}"
  fi
}

# verify_hotkeys_tsv <hotkeys.tsv> — bulk read-back of the whole shortcut baseline
# in ONE export (fast). Honors user rejections via MACOS_SETUP_EXCLUDE.
verify_hotkeys_tsv() {
  local tsv="$1" out line tag f1 f2 seen=0
  out="$(defaults export com.apple.symbolichotkeys - 2>/dev/null \
    | plutil -convert json -o - - 2>/dev/null \
    | /usr/bin/python3 -c '
import json, os, sys
spec = []
for raw in open(sys.argv[1], encoding="utf-8"):
    raw = raw.rstrip("\n")
    if not raw or raw.startswith("#"): continue
    p = raw.split("\t")
    if len(p) >= 2: spec.append((p[0], p[1], p[2] if len(p) > 2 else ""))
ex = set()
exf = os.environ.get("MACOS_SETUP_EXCLUDE", "")
if exf and os.path.exists(exf):
    ex = {l.strip() for l in open(exf, encoding="utf-8")}
try:
    d = json.load(sys.stdin).get("AppleSymbolicHotKeys", {})
except Exception:
    d = {}
good = 0; total = 0
for hid, want, desc in spec:
    if "hotkey:" + hid in ex: continue
    total += 1
    got = str(d.get(hid, {}).get("enabled", "absent")).lower()
    if got == want:
        good += 1
    else:
        print("BAD\thotkey %s (%s) expected %s, got %s" % (hid, desc, want, got))
print("SUM\t%d\t%d" % (good, total))' "$tsv" 2>/dev/null)"
  while IFS=$'\t' read -r tag f1 f2; do
    [ -n "$tag" ] || continue
    seen=1
    case "$tag" in
      BAD) report_finding "$f1" ;;
      SUM) if [ "$f1" = "$f2" ]; then
             report_ok "hotkey baseline: $f1/$f2 match the standard"
           else
             warn "hotkey baseline: $f1/$f2 match (mismatches listed above)"
           fi ;;
    esac
  done <<< "$out"
  [ "$seen" -eq 1 ] || report_finding "could not read com.apple.symbolichotkeys (export/plutil failed)"
}

# ── i18n: voice + banner follow the user's interaction language ──
# Language resolves from MACOS_SETUP_LANG (the agent sets it to match how the user is
# talking to it), else the system UI locale, else English. Voice picks a matching `say`
# voice so a zh user hears Mandarin, not an English voice stumbling over Chinese.
# Add a language by extending the case blocks in msg_i18n / say_voice — nothing else.
setup_lang() {
  local l="${MACOS_SETUP_LANG:-}"
  [ -z "$l" ] && l="$(defaults read -g AppleLocale 2>/dev/null || printf '%s' "${LANG:-}")"
  case "$l" in zh*|*zh_*|*Hans*|*Hant*) printf 'zh' ;; *) printf 'en' ;; esac
}
MACOS_SETUP_LANG_RESOLVED="$(setup_lang)"

# say_voice — a `say -v` voice name for the resolved language, or empty (system default).
say_voice() {
  case "$MACOS_SETUP_LANG_RESOLVED" in
    zh) for v in Tingting Sinji Meijia Li-mu Han; do
          say -v '?' 2>/dev/null | grep -q "^$v " && { printf '%s' "$v"; return; }
        done ;;
  esac
}

# msg_i18n <key> [arg] — localized assist text. The agent calls assist_notify with a KEY,
# not an English sentence, so voice + banner are spoken in the user's language. $1 is the
# arg interpolated where {} appears. Unknown keys fall through verbatim (back-compat: an
# old-style raw English string still works).
msg_i18n() {
  local key="$1" arg="${2:-}" zh en
  case "$key" in
    brew_failed)   en="Homebrew install failed. Check the network or install it by hand."
                   zh="Homebrew 安装失败，请检查网络或手动安装。" ;;
    appstore_signin) en="App Store apps failed to install. Check the App Store is signed in, then tell me to re-run."
                     zh="App Store 应用没装上，请确认 App Store 已登录，再让我重新运行流水线。" ;;
    report_gated)  en="The comparison report is open on your Desktop. {} prerequisite(s) need your help first — tell me when they are done."
                   zh="对比报告已在桌面打开，有 {} 项前置条件需要你先处理，完成后告诉我。" ;;
    report_ready)  en="The device-versus-standard report is open on your Desktop. Review each pending item, then click Copy for Claude Code."
                   zh="设备对比报告已在桌面打开，请逐项确认，然后点「复制给 Claude Code」。" ;;
    sudo_power)    en="Setting never-sleep on AC power needs your password. Help me, then ask me to re-run."
                   zh="设置「接电源永不休眠」需要你的密码，处理后让我重新运行。" ;;
    offline_ready) en="Your bring-your-own apps are staged on the Desktop. Open the guide to install them."
                   zh="你自备的 App 已放到桌面，打开指南即可逐个安装。" ;;
    assist_prefix) en="macOS setup needs your help: " ; zh="macOS 装机需要你协助：" ;;
    reminder)      en="(reminder {} of 3)" ; zh="（第 {} 次提醒，共 3 次）" ;;
    *) printf '%s' "$key"; return ;;   # unknown key → verbatim (raw-string back-compat)
  esac
  local out; [ "$MACOS_SETUP_LANG_RESOLVED" = zh ] && out="$zh" || out="$en"
  printf '%s' "${out//\{\}/$arg}"
}

# ── human-assist protocol: reach the human on the target machine ──
# Two channels per notify: a banner notification (volume-proof) + audible voice.
# speak_audibly <text> — voice that is actually heard: `say` exits 0 even when the
# output is muted or at volume 0, so read the volume first; if muted or below the
# floor (MACOS_SETUP_VOICE_VOLUME, default 50), raise it for the announcement and
# restore the user's exact volume/mute state right after. Non-adjustable outputs
# (e.g. HDMI display audio) report no numeric volume → just speak.
speak_audibly() {
  local text="$1" floor="${MACOS_SETUP_VOICE_VOLUME:-50}" vol muted target voice vopt
  voice="$(say_voice)"; vopt=(); [ -n "$voice" ] && vopt=(-v "$voice")
  vol="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
  muted="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)"
  case "$vol" in *[!0-9]*|'') vol="" ;; esac
  if [ -n "$vol" ] && { [ "$muted" = "true" ] || [ "$vol" -lt "$floor" ]; }; then
    target="$floor"; [ "$vol" -gt "$floor" ] && target="$vol"
    osascript -e "set volume output volume $target without output muted" 2>/dev/null
    /usr/bin/say "${vopt[@]}" "$text" 2>/dev/null     # synchronous: finish, then restore
    osascript -e "set volume output volume $vol" 2>/dev/null
    [ "$muted" = "true" ] && osascript -e 'set volume output muted true' 2>/dev/null
  else
    /usr/bin/say "${vopt[@]}" "$text" 2>/dev/null
  fi
}

# assist_notify <text>: notify once, immediately (called at a manual breakpoint).
# The agent layer then polls for the user's response and calls
# assist_remind_or_silent on each empty poll: at most 3 reminders, then silence.
# MACOS_SETUP_NO_VOICE=1 keeps it silent (banner + log only).
# assist_notify <key> [arg] [suffix] — <key> is an msg_i18n key (or a raw string for
# back-compat); the resolved text is spoken AND shown in the user's language. Optional
# suffix is appended to the spoken/shown text (used for the reminder count).
ASSIST_COUNT_FILE="/tmp/macos-setup-assist-count"
assist_notify() {
  local m; m="$(msg_i18n "$1" "${2:-}")"; [ -n "${3:-}" ] && m="$m ${3}"
  local clean
  warn "needs human assist: $m"
  clean="${m//\"/}"; clean="${clean//\\/}"
  osascript -e "display notification \"$clean\" with title \"macos-setup\"" >/dev/null 2>&1
  if [ "${MACOS_SETUP_NO_VOICE:-0}" != "1" ] && [ -x /usr/bin/say ]; then
    speak_audibly "$(msg_i18n assist_prefix)$m" &
  fi
  printf '%s\t%s\n' "$(date '+%H:%M:%S')" "$m" >> /tmp/macos-setup-assist.log
}
assist_remind_or_silent() {
  local key="$1" arg="${2:-}" n
  n="$(cat "$ASSIST_COUNT_FILE" 2>/dev/null || echo 0)"
  if [ "$n" -lt 3 ]; then
    assist_notify "$key" "$arg" "$(msg_i18n reminder "$((n+1))")"
    echo $((n+1)) > "$ASSIST_COUNT_FILE"
  else
    msg "  (3 reminders sent — staying silent, waiting for the user)"
  fi
}
