#!/usr/bin/env bash
# adopt-pass.sh — pre-bundle step: take over manually installed apps, losslessly.
# Problem: `brew bundle install` fails when /Applications already has an app that
# brew does not manage ("It seems there is already an App at ...").
# Fix: for every cask in the Brewfile whose app exists but is unmanaged, run
# `brew install --cask --adopt` — no re-download, no app restart, no data touched.
# A version mismatch makes adopt fail → recorded as a finding for human review;
# never fall back to --force (it overwrites). See pitfalls #2.
# Usage: adopt-pass.sh <Brewfile>...
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

[ $# -ge 1 ] || { fail "usage: adopt-pass.sh <Brewfile>..."; exit 1; }

installed_casks="$(brew list --cask 2>/dev/null)"

for bf in "$@"; do
  [ -f "$bf" ] || { warn "skipping missing $bf"; continue; }
  msg "── adopt pass: $bf ──"
  grep -E '^\s*cask "' "$bf" | sed -E 's/^\s*cask "([^"]+)".*/\1/' | while read -r c; do
    if printf '%s\n' "$installed_casks" | grep -qx "$c"; then
      continue  # already brew-managed
    fi
    # Does this cask's .app artifact already exist in /Applications (installed by hand)?
    app="$(brew info --cask "$c" 2>/dev/null | sed -n '/Artifacts/,$p' | grep -m1 '\.app' | sed -E 's/^ *([^(]+\.app).*/\1/' | sed -E 's/.*-> *//')"
    if [ -n "$app" ] && [ -e "/Applications/$app" ]; then
      msg "  adopting $c (/Applications/$app exists)"
      if brew install --cask --adopt "$c" >/dev/null 2>&1; then
        report_ok "adopted $c"
      else
        report_finding "adopt $c failed (version mismatch? leave it to brew bundle or review manually — do NOT --force)"
      fi
    fi
  done
done
