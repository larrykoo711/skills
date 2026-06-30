#!/usr/bin/env bash
# d99-killall.sh — restart the processes affected by defaults so changes apply now.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d99 restart affected processes ──"
for app in Dock Finder SystemUIServer cfprefsd; do
  killall "$app" >/dev/null 2>&1 || true
done
ok "Dock / Finder / SystemUIServer / cfprefsd restarted"
msg "(a few items — appearance, some shortcuts — only fully apply after re-login)"
