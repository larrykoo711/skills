#!/usr/bin/env bash
# pipeline.sh — Step 3: the setup pipeline (idempotent — safe to re-run any time).
# Order: Homebrew → adopt pass → brew bundle (pinned) → pnpm globals → uv tools
#        → Claude Code → defaults/shortcuts/security baseline → [agent-ready] → stage offline installers → verify
# Usage: pipeline.sh [--exclude-file <file>] [--skip-defaults] [--skip-bundle] [--profile agent-node]
#        pipeline.sh --prereqs-only   Xcode CLT + Homebrew only — a blank Mac needs these before
#                                     compare.sh can even render (same on every Mac; no order sheet needed)
#   --profile agent-node: also converge the Agent Device Ready layer (standard/agent-ready.tsv).
#   The profile is remembered in ~/.config/macos-setup/profile, so later verify runs include it.
#   --exclude-file: user rejections from the playground order sheet, one token per
#   line. Bare names skip packages; namespaced tokens (default:/hotkey:/security:/
#   power:) skip individual baseline writes.
# Removals are NOT part of this pipeline (high-risk, separate: cleanup.sh, per-item confirm).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

EXCLUDE="" SKIP_DEFAULTS=0 SKIP_BUNDLE=0 MAS_MISSING=0 PROFILE="" PREREQS_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-file) EXCLUDE="$2"; shift 2 ;;
    --skip-defaults) SKIP_DEFAULTS=1; shift ;;
    --skip-bundle) SKIP_BUNDLE=1; shift ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --prereqs-only) PREREQS_ONLY=1; shift ;;
    *) fail "unknown argument: $1"; exit 1 ;;
  esac
done

case "$PROFILE" in ''|agent-node) ;; *) fail "unknown profile: $PROFILE (known: agent-node)"; exit 1 ;; esac
if [ -n "$PROFILE" ]; then
  mkdir -p "$(dirname "$PROFILE_FILE")" && printf '%s\n' "$PROFILE" > "$PROFILE_FILE"
else
  PROFILE="$(current_profile)"     # a machine set up as agent-node stays one on re-runs
fi

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
# Hold off idle sleep for the whole run: a fresh Mac sleeps after ~10 min idle and a
# long brew bundle is not user activity — the machine would vanish mid-install.
have caffeinate && { caffeinate -i -w $$ & }
msg "════ macos-setup pipeline @ $(scutil --get LocalHostName 2>/dev/null) ════"

# ── 0. agent-node: stay awake from the first minute, not from step 6 ──
# A fresh Mac mini ships with system sleep = 1 min; caffeinate covers this run, the
# pmset write covers the gap between runs (and the reboot before the next one).
if [ "$PROFILE" = agent-node ]; then
  for id in power-never-sleep power-autorestart power-womp; do bash "$SCRIPT_DIR/agent-ready.sh" --apply --only "$id" >/dev/null 2>&1; done
fi

# ── 1. Xcode CLT (headless when sudo is passwordless) + Homebrew ──
ensure_clt || true      # brew's installer retries CLT itself; a finding is already recorded
ensure_brew || { assist_notify brew_failed; exit 1; }
if [ "$PREREQS_ONLY" -eq 1 ]; then
  xcode-select -p >/dev/null 2>&1 || { report_finding "Xcode CLT still missing"; exit 1; }
  msg "════ prerequisites ready (CLT + Homebrew) — next: compare.sh ════"; exit 0
fi

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
      # Name what is actually missing — one bad entry aborts the whole bundle, so a
      # generic "App Store signed out?" guess sends the human the wrong way.
      # brew 7 prints the "→ …" list on stderr — keep it, or the count silently reads 0.
      missing="$(brew bundle check --verbose --no-upgrade --file="$BF_RUN" 2>&1 | grep '^→')"
      report_finding "bundle not fully satisfied — $(printf '%s\n' "$missing" | grep -c .) missing: $(printf '%s\n' "$missing" | awk '{print $3}' | tr '\n' ' ')(see the brew error above; inspect: brew bundle check --verbose --file=$BF_RUN)"
      # Sign-in cannot be read from the CLI (pitfalls #10): only a failed mas install
      # is evidence, so that is the only case that asks the human to check it.
      if printf '%s\n' "$missing" | grep -q '^→ App '; then
        MAS_MISSING=1
        assist_notify appstore_signin
      fi
    fi
  fi
fi

# ── 2a. Xcode from the App Store is not usable until it is the active developer dir and
#        its license is accepted — xcodebuild otherwise fails while xcode-select still points
#        at CLT (seen on a first checkup). Needs sudo; the license step is non-interactive.
if [ -d /Applications/Xcode.app ]; then
  if [ "$(xcode-select -p 2>/dev/null)" = /Applications/Xcode.app/Contents/Developer ] && xcodebuild -version >/dev/null 2>&1; then
    report_ok "Xcode is the active developer dir ($(xcodebuild -version 2>/dev/null | head -1))"
  elif sudo -n true 2>/dev/null; then
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer \
      && sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch >/dev/null 2>&1
    xcodebuild -version >/dev/null 2>&1 && report_ok "Xcode activated ($(xcodebuild -version | head -1); license accepted)" \
      || report_finding "Xcode activation failed — sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept"
  else
    report_finding "Xcode installed but not active and no passwordless sudo — sudo xcode-select -s /Applications/Xcode.app"
  fi
fi

# ── 2b. Node runtime: fnm is in the bundle, but a version manager is not a runtime.
#        Without this a fresh Mac has no node/npx (pnpm 12 is a standalone binary), and
#        anything launched with npx — MCP servers, wrangler — fails. LTS, set as default.
if have fnm; then
  if fnm list 2>/dev/null | grep -q 'default'; then
    report_ok "fnm default Node present ($(fnm exec --using default node --version 2>/dev/null))"
  else
    msg "── Node LTS via fnm ──"
    fnm install --lts >/dev/null 2>&1      # the first version fnm installs becomes its default
    fnm list 2>/dev/null | grep -q 'default' && report_ok "Node LTS installed and set as fnm default" \
      || report_finding "fnm install --lts failed — run it by hand: fnm install --lts"
  fi
fi

# ── 3. Node globals (pnpm -g only) ──
if have pnpm; then
  msg "── pnpm globals ──"
  # pnpm refuses `add -g` unless its global bin dir is on PATH (pnpm 12:
  # $PNPM_HOME/bin, older: $PNPM_HOME). Set it for this run rather than calling
  # `pnpm setup`, which also drops a pnpm self-shim that can point at an install
  # that does not exist (pitfalls #32). Persisting PATH belongs in ~/.zshenv.
  export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
  export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"
  grep -vE '^\s*(#|$)' "$SKILL_DIR/standard/node-globals.txt" | while IFS=$'\t' read -r bin pkg; do
    excluded "$bin" && { msg "  skip $bin (rejected by user)"; continue; }
    if have "$bin"; then report_ok "pnpm -g $bin present"; else
      pnpm add -g "$pkg" >/dev/null 2>&1 && report_ok "pnpm add -g $pkg" || report_finding "pnpm add -g $pkg failed"
    fi
  done
  # Scripts, `ssh host cmd` and agents run non-interactive shells: if those
  # can't see the globals, they read as missing there even though installed.
  case ":$(zsh -lc 'echo $PATH' 2>/dev/null):" in
    *":$PNPM_HOME/bin:"*|*":$PNPM_HOME:"*) report_ok "pnpm global bin dir on the non-interactive PATH" ;;
    *) report_finding "pnpm global bin dir ($PNPM_HOME/bin) not on the non-interactive PATH — add it to PATH in ~/.zshenv" ;;
  esac
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

# ── 6b. Agent Device Ready layer (profile agent-node only; every fix read back) ──
if [ "$PROFILE" = agent-node ]; then
  bash "$SCRIPT_DIR/agent-ready.sh" --apply || msg "  agent-ready: items left — see the summary above (manual ones need a human once)"
fi

# ── 7. Stage offline installers to the Desktop + bilingual guide (human installs them) ──
bash "$SCRIPT_DIR/stage-offline-apps.sh" || true

# ── 8. Full verification ──
bash "$SCRIPT_DIR/verify.sh"

msg ""
msg "════ remaining manual breakpoints ════"
[ "$MAS_MISSING" -eq 1 ] && msg "  □ App Store apps not installed — check App Store sign-in, then re-run (re-entry is free)"
have rustup && rustup show >/dev/null 2>&1 || msg "  □ rustup-init (Rust toolchain bootstrap)"
msg "  □ FileVault / SIP — see findings if not enabled"
msg "  □ blocklist cleanup runs separately: cleanup.sh (per-item confirm)"
msg "findings: $FINDINGS_FILE"
msg "════ pipeline complete ════"
