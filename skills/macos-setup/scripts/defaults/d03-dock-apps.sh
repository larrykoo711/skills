#!/usr/bin/env bash
# d03-dock-apps.sh — Dock pinned apps + order from standard/dock-apps.txt (via dockutil).
# Converges ORDER only: standard apps first, then every other app the user pinned, in its
# current order. Nothing is ever unpinned (removals are never automatic). Backs up the Dock
# plist, rewrites only when the order differs, reads the Dock back. Folders stay as they are.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d03 Dock apps ──"
cfg_excluded "dock:apps" && { msg "  skip Dock apps (rejected by user)"; exit 0; }
have dockutil || { report_finding "dockutil missing (brew install dockutil) — Dock apps not converged"; exit 0; }

STD="$SCRIPT_DIR/../../standard/dock-apps.txt"
expected="$(dock_expected)"

if [ "$(dock_current)" = "$expected" ]; then
  report_ok "Dock apps match the standard ($(dock_standard_present | grep -c .) standard pinned, order converged)"
  exit 0
fi

# Back up before rewriting — the Dock plist is the only record of the user's own arrangement.
bk="${MACOS_SETUP_TASK_DIR:-/tmp}/raw/dock-before-$(date +%Y%m%d%H%M%S).plist"
mkdir -p "$(dirname "$bk")" && cp "$HOME/Library/Preferences/com.apple.dock.plist" "$bk" 2>/dev/null \
  || { report_finding "could not back up the Dock plist — Dock left untouched"; exit 0; }

# Reorder = remove each app tile, add back in the target order. Only the apps section is touched
# (folders like Downloads stay); every app that was pinned is pinned again.
paths="$(dockutil --list 2>/dev/null | awk -F'\t' '$2 ~ /\.app\/?$/ {print $2}')"
path_of() {  # app name → its current or standard path
  printf '%s\n' "$paths" | /usr/bin/python3 -c 'import sys,urllib.parse,os
want=sys.argv[1]
for l in sys.stdin:
    p=urllib.parse.unquote(l.strip()).replace("file://","").rstrip("/")
    if os.path.basename(p)[:-4]==want: print(p); break' "$1"
}
order="$(printf '%s\n' "$expected")"
resolved="$(printf '%s\n' "$order" | while IFS= read -r name; do
  p="$(grep -vE '^\s*(#|$)' "$STD" | while IFS= read -r app; do [ "$(basename "$app" .app)" = "$name" ] && [ -d "$app" ] && echo "$app"; done | head -1)"
  [ -n "$p" ] || p="$(path_of "$name")"
  [ -n "$p" ] && echo "$p"
done)"
printf '%s\n' "$paths" | while IFS= read -r url; do [ -n "$url" ] && dockutil --remove "$url" --no-restart >/dev/null 2>&1; done
printf '%s\n' "$resolved" | while IFS= read -r app; do [ -n "$app" ] && dockutil --add "$app" --no-restart >/dev/null 2>&1; done
killall Dock 2>/dev/null; sleep 2

if [ "$(dock_current)" = "$expected" ]; then
  report_ok "Dock apps set: $(printf '%s\n' "$expected" | paste -sd, -) (backup: $bk)"
else
  report_finding "Dock apps differ after write — expected: $(printf '%s\n' "$expected" | paste -sd, -); got: $(dock_current | paste -sd, -); restore with: cp $bk ~/Library/Preferences/com.apple.dock.plist && killall Dock"
fi
