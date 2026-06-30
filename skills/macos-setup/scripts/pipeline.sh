#!/usr/bin/env bash
# pipeline.sh — Step 3: the setup pipeline (idempotent — safe to re-run any time).
# Order: Homebrew → adopt pass → brew bundle (pinned) → pnpm globals → uv tools
#        → Claude Code → defaults/shortcuts/security baseline → stage offline installers → verify
# Usage: pipeline.sh [--exclude-file <file>] [--skip-defaults] [--skip-bundle]
#   --exclude-file: user rejections from the playground order sheet, one token per
#   line. Bare names skip packages; namespaced tokens (default:/hotkey:/security:/
#   power:) skip individual baseline writes.
# Removals are NOT part of this pipeline (high-risk, separate: cleanup.sh, per-item confirm).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

EXCLUDE="" SKIP_DEFAULTS=0 SKIP_BUNDLE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-file) EXCLUDE="$2"; shift 2 ;;
    --skip-defaults) SKIP_DEFAULTS=1; shift ;;
    --skip-bundle) SKIP_BUNDLE=1; shift ;;
    *) fail "unknown argument: $1"; exit 1 ;;
  esac
done

excluded() { [ -n "$EXCLUDE" ] && [ -f "$EXCLUDE" ] && grep -qxF "$1" "$EXCLUDE"; }
# Baseline scripts read the same file for namespaced config tokens (see lib cfg_excluded).
[ -n "$EXCLUDE" ] && [ -f "$EXCLUDE" ] && export MACOS_SETUP_EXCLUDE="$EXCLUDE"

BF_STD="$SKILL_DIR/standard/Brewfile.standard"
# Archive the order sheet's exclude list into the run's task dir, if one is active.
if [ -n "${MACOS_SETUP_TASK_DIR:-}" ] && [ -d "$MACOS_SETUP_TASK_DIR/artifacts" ]; then
  [ -n "$EXCLUDE" ] && [ -f "$EXCLUDE" ] && cp "$EXCLUDE" "$MACOS_SETUP_TASK_DIR/artifacts/exclude.txt" 2>/dev/null
fi
mkdir -p "$(dirname "$FINDINGS_FILE")" 2>/dev/null    # ensure raw/ exists when TASK_DIR is set
: > "$FINDINGS_FILE"; rm -f "$ASSIST_COUNT_FILE"
msg "════ macos-setup pipeline @ $(scutil --get LocalHostName 2>/dev/null) ════"

# ── 1. Homebrew ──
ensure_brew || { assist_notify brew_failed; exit 1; }

# ── 2. Software standard (apply exclusions → adopt → bundle) ──
if [ "$SKIP_BUNDLE" -eq 0 ]; then
  BF_RUN="$BF_STD"
  if [ -n "$EXCLUDE" ] && [ -f "$EXCLUDE" ]; then
    BF_RUN="/tmp/Brewfile.run"
    # Drop rejected brew/cask/mas lines (match by full or short name).
    # POSIX awk only — no GNU match(s, r, arr); macOS ships BSD awk.
    if ! awk -v ex="$EXCLUDE" '
      BEGIN { while ((getline l < ex) > 0) if (l != "") skip[l] = 1 }
      {
        keep = 1
        if (match($0, /^(brew|cask|mas) "[^"]+"/)) {
          s = substr($0, RSTART, RLENGTH)
          sub(/^[a-z]+ "/, "", s); sub(/"$/, "", s)
          n = s; sub(/.*\//, "", n)
          if (s in skip || n in skip) keep = 0
        }
        if (keep) print
      }' "$BF_STD" > "$BF_RUN"; then
      report_finding "failed to apply the exclude list to the Brewfile — aborting (refusing to install rejected items)"
      exit 1
    fi
    msg "exclude list applied: $(grep -c . "$EXCLUDE") token(s)"
  fi
  bash "$SCRIPT_DIR/adopt-pass.sh" "$BF_RUN"
  # No lockfile in Homebrew: never let a setup re-run upgrade everything (pitfalls #7).
  export HOMEBREW_BUNDLE_NO_UPGRADE=1
  # Third-party taps the standard deliberately trusts (steipete/tap, antoniorodr/memo).
  # Recent Homebrew gates untrusted taps behind a prompt that will hard-fail in a later
  # release; the standard's taps are vetted, so opt them through non-interactively here
  # (scoped to this bundle run, not the user's global env). See pitfalls #20.
  export HOMEBREW_NO_REQUIRE_TAP_TRUST=1
  msg "── brew bundle (standard) ──"
  if brew bundle check --file="$BF_RUN" >/dev/null 2>&1; then
    report_ok "standard bundle already satisfied"
  else
    brew bundle install --file="$BF_RUN" 2>&1 | tail -6
    if brew bundle check --file="$BF_RUN" >/dev/null 2>&1; then
      report_ok "standard bundle complete"
    else
      report_finding "bundle not fully satisfied (App Store signed out? inspect: brew bundle check --file=$BF_RUN)"
      [ -n "$(mas list 2>/dev/null | head -1)" ] || \
        assist_notify appstore_signin
    fi
  fi
fi

# ── 3. Node globals (pnpm -g only) ──
if have pnpm; then
  msg "── pnpm globals ──"
  grep -vE '^\s*(#|$)' "$SKILL_DIR/standard/node-globals.txt" | while IFS=$'\t' read -r bin pkg; do
    excluded "$bin" && { msg "  skip $bin (rejected by user)"; continue; }
    if have "$bin"; then report_ok "pnpm -g $bin present"; else
      pnpm add -g "$pkg" >/dev/null 2>&1 && report_ok "pnpm add -g $pkg" || report_finding "pnpm add -g $pkg failed"
    fi
  done
fi

# ── 4. uv tools ──
if have uv; then
  msg "── uv tools ──"
  grep -vE '^\s*(#|$)' "$SKILL_DIR/standard/uv-tools.txt" | while IFS=$'\t' read -r bin pkg; do
    excluded "$bin" && { msg "  skip $bin (rejected by user)"; continue; }
    if have "$bin"; then report_ok "uv tool $bin present"; else
      uv tool install "$pkg" >/dev/null 2>&1 && report_ok "uv tool install $pkg" || report_finding "uv tool install $pkg failed"
    fi
  done
fi

# ── 5. Claude Code (official installer → ~/.local/bin/claude) ──
if have claude; then report_ok "Claude Code present ($(claude --version 2>/dev/null | head -1))"; else
  msg "── installing Claude Code ──"
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
    && report_ok "Claude Code installed" || report_finding "Claude Code install failed (network?)"
fi

# ── 6. defaults / shortcuts / security baseline (every write read back) ──
if [ "$SKIP_DEFAULTS" -eq 0 ]; then
  for d in "$SCRIPT_DIR"/defaults/d[0-9][0-9]-*.sh; do bash "$d"; done
fi

# ── 7. Stage offline installers to the Desktop + bilingual guide (human installs them) ──
bash "$SCRIPT_DIR/stage-offline-apps.sh" || true

# ── 8. Full verification ──
bash "$SCRIPT_DIR/verify.sh"

msg ""
msg "════ remaining manual breakpoints ════"
[ -n "$(mas list 2>/dev/null | head -1)" ] || msg "  □ App Store sign-in (re-run the pipeline after — re-entry is free)"
have rustup && rustup show >/dev/null 2>&1 || msg "  □ rustup-init (Rust toolchain bootstrap)"
msg "  □ FileVault / SIP — see findings if not enabled"
msg "  □ blocklist cleanup runs separately: cleanup.sh (per-item confirm)"
msg "findings: $FINDINGS_FILE"
msg "════ pipeline complete ════"
