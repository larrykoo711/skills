#!/usr/bin/env bash
# d05-security.sh — security baseline: Firewall / SIP / FileVault all on.
# Firewall write needs sudo; SIP and FileVault are read-only checks here
# (enabling them takes Recovery Mode / GUI — human breakpoints).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d05 security baseline ──"

FW="/usr/libexec/ApplicationFirewall/socketfilterfw"

# Application Firewall: on. It is app-level, not port-level — it does not break
# SSH, VPN meshes, or container runtimes (allow prompts appear per app).
if cfg_excluded "security:firewall"; then
  msg "  skip firewall (rejected by user)"
elif "$FW" --getglobalstate 2>/dev/null | grep -q "enabled"; then
  report_ok "Application Firewall on"
else
  warn "firewall off — enabling (needs sudo)…"
  if sudo -n true 2>/dev/null || sudo -v; then
    sudo "$FW" --setglobalstate on >/dev/null 2>&1
    "$FW" --getglobalstate 2>/dev/null | grep -q "enabled" \
      && report_ok "Application Firewall on" \
      || report_finding "enabling the firewall failed — System Settings → Network → Firewall"
  else
    report_finding "no sudo — firewall left off (manual breakpoint)"
  fi
fi

# SIP: read-only check
csrutil status 2>/dev/null | grep -q "enabled" \
  && report_ok "SIP enabled" \
  || report_finding "SIP disabled (Recovery Mode: csrutil enable — manual breakpoint)"

# FileVault: read-only check
fdesetup status 2>/dev/null | grep -q "On" \
  && report_ok "FileVault on" \
  || report_finding "FileVault off (System Settings → Privacy & Security → FileVault — manual breakpoint)"
