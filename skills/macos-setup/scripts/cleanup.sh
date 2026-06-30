#!/usr/bin/env bash
# cleanup.sh — blocklist convergence: for every blocklisted item present on this
# machine, ask y/N and remove on explicit "y" only.
# HIGH RISK — the pipeline never calls this. Run it only when the user explicitly
# asks to converge. App data is never touched (programs ≠ data; see pitfalls #8).
# Usage: cleanup.sh [--exclude-file <file>]   # exclude = removals the user rejected
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

EXCLUDE=""
[ "${1:-}" = "--exclude-file" ] && EXCLUDE="${2:-}"
excluded() { [ -n "$EXCLUDE" ] && [ -f "$EXCLUDE" ] && grep -qxF "$1" "$EXCLUDE"; }

# Execution ledger — append every item we actually remove, so compare.sh can show it as
# `removed ✓` (a now-absent blocklist item we never touched stays hidden). Same path as
# compare.sh derives. No-op into /tmp when no task dir is active.
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
RAW="${MACOS_SETUP_TASK_DIR:+$MACOS_SETUP_TASK_DIR/raw}"; RAW="${RAW:-/tmp}"
LEDGER="${MACOS_SETUP_LEDGER:-$RAW/macos-setup-executed-$HOST.tsv}"
mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true
ledger() { printf 'removed\t%s\t%s\n' "$1" "$2" >> "$LEDGER"; }

LIST="$SKILL_DIR/standard/blocklist.txt"
msg "════ blocklist cleanup @ $(scutil --get LocalHostName 2>/dev/null) — per-item confirm, 'y' executes ════"

grep -vE '^\s*(#|$)' "$LIST" | while IFS=$'\t' read -r type name; do
  # The order sheet exports short names — match both full (tap path) and short.
  if excluded "$name" || excluded "$(basename "$name")"; then
    msg "  skip $name (rejected by user)"; continue
  fi
  # Skip silently when the item is not present. Presence checks must mirror how compare.sh
  # / collect.sh detect each kind, or cleanup misses an item that IS installed:
  #   cask  — match both `<name>` and `<name>-app` (Homebrew rename, see has_cask / pitfalls #22)
  #   pnpm-g — check the shim in $PNPM_HOME/bin, not `pnpm ls -g` (multi-store / node, pitfalls #25)
  PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
  case "$type" in
    formula)  brew list --formula 2>/dev/null | grep -qx "$(basename "$name")" || continue ;;
    cask)     brew list --cask 2>/dev/null | grep -qxE "$name|${name}-app" || continue ;;
    app)      [ -e "/Applications/$name.app" ] || continue ;;
    pnpm-g)   [ -e "$PNPM_HOME/bin/$name" ] || continue ;;
    uv-tool)  uv tool list 2>/dev/null | grep -q "^$name" || continue ;;
    local-bin) [ -e "$HOME/.local/bin/$name" ] || continue ;;
    *) continue ;;
  esac
  printf '%s[%s]%s remove %s ? [y/N] ' "$YLW" "$type" "$NC" "$name"
  read -r ans </dev/tty
  [ "$ans" = "y" ] || { msg "  keeping $name"; continue; }
  case "$type" in
    formula)   brew uninstall "$name" >/dev/null 2>&1 && { report_ok "removed formula $name"; ledger formula "$name"; } || report_finding "remove $name failed (depended on? run: brew uninstall $name)" ;;
    cask)      brew uninstall --cask "$name" >/dev/null 2>&1 && { report_ok "removed cask $name"; ledger cask "$name"; } || report_finding "remove cask $name failed" ;;
    app)       rm -rf "/Applications/$name.app" && { report_ok "removed $name.app"; ledger app "$name"; } || report_finding "remove $name.app failed (permissions?)" ;;
    pnpm-g)    pnpm remove -g "$name" >/dev/null 2>&1 && { report_ok "pnpm remove -g $name"; ledger pnpm-g "$name"; } || report_finding "pnpm remove $name failed" ;;
    uv-tool)   uv tool uninstall "$name" >/dev/null 2>&1 && { report_ok "uv tool uninstall $name"; ledger uv-tool "$name"; } || report_finding "uv tool uninstall $name failed" ;;
    local-bin) rm -f "$HOME/.local/bin/$name" && { report_ok "removed ~/.local/bin/$name"; ledger local-bin "$name"; } ;;
  esac
done
msg "════ cleanup done (leftover preferences: review with AppCleaner; app data like ~/.ollama is kept by design) ════"
