#!/usr/bin/env bash
# precheck.sh — Step 1: prerequisite check for the target Mac (read-only).
# Verifies everything the pipeline will need, in one pass. Result levels:
#   pass   — ready
#   block  — must be fixed before anything else (exit 1)
#   manual — human breakpoint; the pipeline reminds via voice when it gets there
#   info   — needs a human present at execution time (e.g. sudo); not a gate
# Set PRECHECK_TSV=<path> to emit structured results for compare.sh:
#   <status>TAB<description-en>TAB<description-zh>   (zh feeds the bilingual report)
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

PASS=0; BLOCK=0; MANUAL=0
TSV="${PRECHECK_TSV:-}"
[ -n "$TSV" ] && : > "$TSV"
# helpers take <en> [zh]; terminal prints English, TSV carries both
emit()   { [ -n "$TSV" ] && printf '%s\t%s\t%s\n' "$1" "$2" "${3:-$2}" >> "$TSV"; }
chk()    { ok "$1"; PASS=$((PASS+1)); emit pass "$1" "${2:-}"; }
blk()    { fail "[BLOCK] $1"; BLOCK=$((BLOCK+1)); emit block "$1" "${2:-}"; }
manual() { warn "[MANUAL] $1"; MANUAL=$((MANUAL+1)); emit manual "$1" "${2:-}"; }
note()   { msg "  ℹ $1"; emit info "$1" "${2:-}"; }

msg "════ macos-setup precheck @ $(scutil --get LocalHostName 2>/dev/null) ════"

# 1. macOS version (the standard targets macOS 14+)
ver="$(sw_vers -productVersion)"
if [ "${ver%%.*}" -ge 14 ] 2>/dev/null; then
  # NOTE: always brace variables before full-width CJK punctuation — in a non-UTF-8
  # locale bash can swallow multibyte bytes into the identifier ("ver�: unbound").
  chk "macOS $ver (>= 14)" "macOS ${ver}（≥ 14）"
else
  blk "macOS $ver is too old (standard requires >= 14)" "macOS $ver 过旧（标准要求 ≥ 14）"
fi

# 2. Architecture
arch="$(uname -m)"
if [ "$arch" = "arm64" ]; then
  chk "Apple Silicon ($arch)" "Apple Silicon（${arch}）"
else
  note "Intel ($arch): brew prefix is /usr/local — scripts are compatible but less battle-tested" \
       "Intel（${arch}）：brew 前缀为 /usr/local——脚本兼容，但实战验证较少"
fi

# 3. Free disk space >= 30 GB (the full standard needs ~20 GB)
free_gb="$(df -g / 2>/dev/null | awk 'NR==2{print $4}')"
if [ "${free_gb:-0}" -ge 30 ]; then
  chk "free disk ${free_gb} GB" "磁盘空闲 ${free_gb} GB"
else
  blk "only ${free_gb} GB free (< 30 GB)" "磁盘空闲仅 ${free_gb} GB（< 30 GB）"
fi

# 4. Network reachability (Homebrew install source)
if curl -sf --connect-timeout 8 -o /dev/null https://raw.githubusercontent.com 2>/dev/null; then
  chk "raw.githubusercontent.com reachable" "raw.githubusercontent.com 可达"
else
  blk "GitHub unreachable — check network/proxy, then re-run" "GitHub 不可达——检查网络/代理后重跑"
fi

# 5. sudo (needed for firewall / pkg installs; execution-time, not a gate)
if sudo -n true 2>/dev/null; then
  chk "passwordless sudo available" "sudo 免密可用"
else
  note "sudo needs a password: be present when the pipeline reaches firewall/pkg steps (it will remind by voice)" \
       "sudo 需要密码：流水线执行到防火墙/pkg 步骤时请在场（会语音提醒）"
fi

# 6. Full Disk Access probe — heuristic for the silent-defaults-failure trap (pitfalls #1)
if defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys >/dev/null 2>&1; then
  chk "protected defaults domain readable (FDA likely granted)" "受保护 defaults 域可读（FDA 大概率已授权）"
else
  manual "this terminal may lack Full Disk Access: System Settings → Privacy & Security → Full Disk Access — without it, defaults writes fail silently" \
         "本终端可能缺少完全磁盘访问权限：系统设置→隐私与安全性→完全磁盘访问——否则 defaults 写入会静默失效"
fi

# 7. App Store sign-in (hard prerequisite for mas, pitfalls #5).
#    mas 7.x removed `account` — detect sign-in via `mas list` instead (pitfalls #10).
if command -v mas >/dev/null 2>&1; then
  if [ -n "$(mas list 2>/dev/null | head -1)" ]; then
    chk "App Store signed in (mas list works)" "App Store 已登录（mas list 可用）"
  else
    manual "App Store not signed in: open the App Store app and sign in (mas cannot do it for you)" \
           "App Store 未登录：请打开 App Store 应用登录（mas 无法代登）"
  fi
else
  # Not a human task yet — the pipeline installs mas itself, then re-checks sign-in.
  note "mas not installed — the pipeline installs it, then verifies App Store sign-in (if signed out, the mas section is skipped: sign in and re-run)" \
       "mas 未安装——流水线会自行安装并再查 App Store 登录态（未登录则 mas 段跳过：登录后重跑即可）"
fi

# 8. Xcode Command Line Tools (Homebrew prerequisite)
if xcode-select -p >/dev/null 2>&1; then
  chk "Xcode CLT installed" "Xcode CLT 已装"
else
  manual "Xcode CLT missing: the Homebrew installer will pop a dialog — needs a human click" \
         "Xcode CLT 未装：Homebrew 安装时会弹窗，需要人工点击"
fi

# 9. Homebrew itself
if command -v brew >/dev/null 2>&1; then
  chk "Homebrew installed ($(brew --version | head -1))" "Homebrew 已装（$(brew --version | head -1)）"
else
  note "Homebrew not installed (pipeline step 1 installs it)" "Homebrew 未装（流水线第一步会装）"
fi

# 10. Voice assist channel — `say` succeeds silently when muted/volume 0 (pitfalls #11);
#     speak_audibly raises a floor when speaking, so this is informational, not a gate.
vol="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
muted="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)"
case "$vol" in *[!0-9]*|'') vol="" ;; esac
if [ -n "$vol" ]; then
  if [ "$muted" = "true" ] || [ "$vol" -lt 25 ]; then
    note "output volume ${vol}%$([ "$muted" = "true" ] && printf ', muted') — voice reminders raise it temporarily, then restore it" \
         "输出音量 ${vol}%$([ "$muted" = "true" ] && printf '，已静音')——语音提醒会临时调高播报，随后恢复"
  else
    chk "voice channel ready (output volume ${vol}%)" "语音通道就绪（输出音量 ${vol}%）"
  fi
else
  note "output volume not adjustable (display/HDMI audio?) — voice may be inaudible; banner notifications still appear" \
       "输出音量不可调（显示器/HDMI 音频？）——语音可能听不到；横幅通知仍会显示"
fi

msg ""
msg "════ precheck: ${PASS} pass · ${BLOCK} block · ${MANUAL} manual ════"
[ "$BLOCK" -gt 0 ] && { fail "BLOCK items present — fix them, then re-run precheck"; exit 1; }
[ "$MANUAL" -gt 0 ] && warn "MANUAL items present: the pipeline will ask for help (by voice) when it reaches them"
exit 0
