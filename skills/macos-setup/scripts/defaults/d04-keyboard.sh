#!/usr/bin/env bash
# d04-keyboard.sh — keyboard / trackpad baseline
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/idempotent.sh
. "$SCRIPT_DIR/../lib/idempotent.sh"

msg "── d04 keyboard / trackpad ──"

# Key repeat: fastest tier
write_verify NSGlobalDomain KeyRepeat -int 2
write_verify NSGlobalDomain InitialKeyRepeat -int 15

# Trackpad: tap to click (both built-in and Bluetooth trackpad domains)
write_verify com.apple.AppleMultitouchTrackpad Clicking -bool true 1
write_verify com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true 1

# Three-finger drag — set on every machine, desktops included: it activates the
# moment a trackpad is paired, and is harmless without one.
write_verify com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true 1
write_verify com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true 1
