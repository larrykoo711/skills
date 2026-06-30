#!/usr/bin/env bash
# d06-keybindings.sh — keyboard shortcut baseline (com.apple.symbolichotkeys).
# Data-driven: reads standard/hotkeys.tsv (the single source of truth), writes
# every id, applies via activateSettings, then verifies the whole set in one pass.
# Rationale and read/write methods: references/keybindings-standard.md
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

TSV="$SKILL_DIR/standard/hotkeys.tsv"
msg "── d06 keyboard shortcuts (from standard/hotkeys.tsv) ──"

while IFS=$'\t' read -r id want _desc; do
  case "$id" in ''|'#'*) continue ;; esac
  # 61 needs the full parameter payload, written below — skip the bare toggle.
  [ "$id" = "61" ] && continue
  set_hotkey "$id" "$want"
done < "$TSV"

# Input source switch (61) = the Globe key, with full key parameters:
# [65535 (no ASCII), keycode 105, modifier 8388608 (the Fn/Globe mask)]
if ! cfg_excluded "hotkey:61"; then
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 61 \
    '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>105</integer><integer>8388608</integer></array><key>type</key><string>standard</string></dict></dict>' 2>/dev/null
fi

# Apply without logging out
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || \
  warn "activateSettings unavailable — shortcut changes take effect after re-login"

# Read back the entire baseline (one export, every id)
verify_hotkeys_tsv "$TSV"
