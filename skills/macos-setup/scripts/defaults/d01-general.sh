#!/usr/bin/env bash
# d01-general.sh — general UI / input baseline
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d01 general UI / input ──"

# Appearance: Auto (light/dark follows time of day; full effect after re-login).
# In Auto mode AppleInterfaceStyle is managed dynamically by the system — delete it.
write_verify NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool true 1
defaults delete NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true

# Preferred languages (edit to taste — array values, verified by membership)
if ! cfg_excluded "default:NSGlobalDomain.AppleLanguages"; then
  defaults write NSGlobalDomain AppleLanguages -array "zh-Hans-CN" "en-CN" 2>/dev/null
  defaults read NSGlobalDomain AppleLanguages 2>/dev/null | grep -q "zh-Hans-CN" \
    && report_ok "AppleLanguages = zh-Hans-CN, en-CN" \
    || report_finding "AppleLanguages write did not take effect"
fi

# Developer-friendly typing: no auto-correct, no auto-capitalize
write_verify NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false 0
write_verify NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false 0
