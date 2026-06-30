#!/usr/bin/env bash
# d07-power.sh — power baseline: never sleep on AC power (all machine types).
# Battery settings are left alone on laptops to protect battery life.
# pmset needs sudo; without it, record a finding and move on.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d07 power ──"

if cfg_excluded "power:ac-sleep"; then
  msg "  skip AC sleep (rejected by user)"
  exit 0
fi

cur="$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f && /^ *sleep/{print $2; exit}')"
if [ "${cur:-}" = "0" ]; then
  report_ok "pmset AC sleep already 0 (never sleep on AC)"
else
  if sudo -n true 2>/dev/null || sudo -v 2>/dev/null; then
    sudo pmset -c sleep 0 2>/dev/null
    cur="$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f && /^ *sleep/{print $2; exit}')"
    [ "${cur:-}" = "0" ] && report_ok "pmset -c sleep 0 applied" \
      || report_finding "pmset AC sleep expected 0, got ${cur:-unknown}"
  else
    assist_notify sudo_power
    report_finding "pmset AC sleep not set (no sudo — manual breakpoint)"
  fi
fi
