#!/usr/bin/env bash
# d02-dock.sh — Dock baseline
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d02 Dock ──"

write_verify com.apple.dock magnification -bool true 1
write_verify com.apple.dock autohide -bool false 0
write_verify com.apple.dock show-recents -bool false 0
write_verify com.apple.dock tilesize -int 48
