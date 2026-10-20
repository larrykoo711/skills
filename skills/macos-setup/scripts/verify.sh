#!/usr/bin/env bash
# verify.sh — read-only convergence audit against standard/ (run any time).
# Reads back the entire baseline: bundle, defaults, power, shortcuts, security.
# When MACOS_SETUP_EXCLUDE is set (pipeline run), this run's user rejections are
# skipped; run standalone (no env) to audit against the FULL standard.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

BF_STD="$SKILL_DIR/standard/Brewfile.standard"
# If the pipeline filtered the Brewfile this run, audit against the filtered one.
[ -f "/tmp/Brewfile.run" ] && BF_STD="/tmp/Brewfile.run"

msg "════ macos-setup verify (read-only, against standard/) ════"

# ── software: brew bundle check ──
if brew bundle check --file="$BF_STD" >/dev/null 2>&1; then
  report_ok "standard bundle satisfied: $(basename "$BF_STD")"
else
  report_finding "standard bundle has gaps (details: brew bundle check --file=$BF_STD)"
fi

# ── defaults baseline read-back (must mirror collect.sh and compare.sh) ──
check_default() {
  local domain="$1" key="$2" expect="$3"
  cfg_excluded "default:$domain.$key" && { msg "  skip $domain $key (rejected by user)"; return 0; }
  local got; got="$(defaults read "$domain" "$key" 2>/dev/null)"
  [ "$got" = "$expect" ] && report_ok "$domain $key=$got" \
    || report_finding "$domain $key expected $expect, got ${got:-<unset>}"
}
check_default NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically 1
check_default NSGlobalDomain KeyRepeat 2
check_default NSGlobalDomain InitialKeyRepeat 15
check_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled 0
check_default NSGlobalDomain NSAutomaticCapitalizationEnabled 0
check_default com.apple.AppleMultitouchTrackpad Clicking 1
check_default com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag 1
check_default com.apple.dock magnification 1
check_default com.apple.dock autohide 0
check_default com.apple.dock tilesize 48
check_default com.apple.dock show-recents 0

# ── power: never sleep on AC ──
if ! cfg_excluded "power:ac-sleep"; then
  ac_sleep="$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f && /^ *sleep/{print $2; exit}')"
  [ "${ac_sleep:-}" = "0" ] && report_ok "pmset AC sleep=0" \
    || report_finding "pmset AC sleep expected 0, got ${ac_sleep:-unknown}"
fi

# ── Dock pinned apps + order ──
if ! cfg_excluded "dock:apps" && have dockutil; then
  [ "$(dock_current)" = "$(dock_expected)" ] && report_ok "Dock apps match standard/dock-apps.txt" \
    || report_finding "Dock apps differ from standard/dock-apps.txt (got: $(dock_current | paste -sd, -))"
fi

# ── keyboard shortcuts: the whole baseline in one pass ──
verify_hotkeys_tsv "$SKILL_DIR/standard/hotkeys.tsv"

# ── security baseline ──
if ! cfg_excluded "security:firewall"; then
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q enabled \
    && report_ok "Application Firewall on" || report_finding "Application Firewall off"
fi
if ! cfg_excluded "security:sip"; then
  csrutil status 2>/dev/null | grep -q enabled && report_ok "SIP enabled" || report_finding "SIP disabled"
fi
if ! cfg_excluded "security:filevault"; then
  fdesetup status 2>/dev/null | grep -q On && report_ok "FileVault on" || report_finding "FileVault off"
fi

# ── Agent Device Ready layer (only on machines set up with --profile agent-node) ──
[ "$(current_profile)" = agent-node ] && bash "$SCRIPT_DIR/agent-ready.sh" --check

msg "════ verify done — findings → $FINDINGS_FILE ════"
