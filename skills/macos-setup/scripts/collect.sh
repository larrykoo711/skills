#!/usr/bin/env bash
# collect.sh — Step 2a: read-only snapshot of the target Mac (input for compare.sh).
# Emits TSV to stdout (or to $1): <category>TAB<name>[=<value>]
# Categories: formula cask app mas pnpm-g uv-tool local-bin default security power hotkey
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT="${1:-/dev/stdout}"
{
  # Homebrew. Two formula views, because one list can't answer both questions:
  #   formula      — ALL installed (brew list --formula), incl. those pulled in as
  #                  dependencies. "Is this standard formula present?" must use this, or a
  #                  standard tool that got installed as some other formula's dep reads as
  #                  missing forever (pitfalls #19).
  #   formula-leaf — top-level only (brew leaves). "Is this an off-standard EXTRA?" uses
  #                  this, so the off-standard section isn't flooded with dependency noise.
  if command -v brew >/dev/null 2>&1; then
    brew list --formula 2>/dev/null | sed 's/^/formula\t/'
    brew leaves 2>/dev/null         | sed 's/^/formula-leaf\t/'
    brew list --cask 2>/dev/null    | sed 's/^/cask\t/'
  fi
  # /Applications (includes manually installed apps)
  ls -1 /Applications 2>/dev/null | grep '\.app$' | sed 's/\.app$//' | sed 's/^/app\t/'
  # App Store apps
  # mas list line: "  <id>   <App Name>   (<version>)". The name can hold spaces and CJK,
  # so strip the leading id and the trailing "(version)", then trim — a single greedy sed
  # mis-handled multi-space gaps and CJK and left the whole raw line as the "name", so
  # nothing ever matched the standard's plain "Pages" (pitfalls #23). Also emit the id as
  # `mas-id\t<id>` so compare can match by stable id, not the localized display name.
  command -v mas >/dev/null 2>&1 && mas list 2>/dev/null \
    | sed -E 's/^[[:space:]]*([0-9]+)[[:space:]]+(.+)[[:space:]]+\([^)]*\)[[:space:]]*$/\1\t\2/' \
    | while IFS=$'\t' read -r id name; do
        name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
        printf 'mas\t%s\nmas-id\t%s\n' "$name" "$id"
      done
  # pnpm globals — list the SHIM names in $PNPM_HOME/bin, not `pnpm ls -g`. Two reasons it
  # bit us: (a) `pnpm ls` needs node, fnm-managed and absent from a non-interactive SSH PATH
  # → "env: node: No such file or directory"; (b) `pnpm ls -g`'s answer depends on the active
  # node major (this machine has global/5 AND global/v11 stores; the wrong node reports the
  # wrong store) — so a package that's installed and whose shim works reads as missing
  # (pitfalls #25). The shims in $PNPM_HOME/bin ARE the ground truth for "which global
  # commands actually run", and they're exactly node-globals.txt's first column (bin name).
  # Emit `pnpm-g\t<binname>`; compare matches that against the bin column.
  PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
  [ -d "$PNPM_HOME/bin" ] && ls -1 "$PNPM_HOME/bin" 2>/dev/null | sed 's/^/pnpm-g\t/'
  # uv tools
  command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null \
    | grep -E '^[a-z]' | awk '{print $1}' | sed 's/^/uv-tool\t/'
  # ~/.local/bin
  ls -1 "$HOME/.local/bin" 2>/dev/null | sed 's/^/local-bin\t/'
  # defaults baseline keys (must mirror compare.sh std_cfg and verify.sh)
  for spec in "NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically" \
              "NSGlobalDomain KeyRepeat" "NSGlobalDomain InitialKeyRepeat" \
              "NSGlobalDomain NSAutomaticSpellingCorrectionEnabled" \
              "NSGlobalDomain NSAutomaticCapitalizationEnabled" \
              "com.apple.AppleMultitouchTrackpad Clicking" \
              "com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag" \
              "com.apple.dock magnification" "com.apple.dock autohide" \
              "com.apple.dock tilesize" "com.apple.dock show-recents"; do
    # shellcheck disable=SC2086
    v="$(defaults read $spec 2>/dev/null || echo '<unset>')"
    printf 'default\t%s=%s\n' "${spec// /.}" "$v"
  done
  # power: sleep on AC power
  ac_sleep="$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f && /^ *sleep/{print $2; exit}')"
  printf 'power\tac-sleep=%s\n' "${ac_sleep:-<unset>}"
  # security
  printf 'security\tfirewall=%s\n' "$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q enabled && echo on || echo off)"
  printf 'security\tsip=%s\n' "$(csrutil status 2>/dev/null | grep -q enabled && echo on || echo off)"
  printf 'security\tfilevault=%s\n' "$(fdesetup status 2>/dev/null | grep -q On && echo on || echo off)"
  # keyboard shortcuts — every id in the standard (read at plutil-JSON level, pitfalls #6)
  ids="$(awk -F'\t' '$0 !~ /^#/ && NF>=2 {printf "%s ", $1}' "$SKILL_DIR/standard/hotkeys.tsv" 2>/dev/null)"
  [ -n "$ids" ] && defaults export com.apple.symbolichotkeys - 2>/dev/null \
    | plutil -convert json -o - - 2>/dev/null \
    | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)["AppleSymbolicHotKeys"]
except Exception:
    d = {}
for k in sys.argv[1].split():
    print("hotkey\t%s=%s" % (k, str(d.get(k, {}).get("enabled", "absent")).lower()))' "$ids" 2>/dev/null
} > "$OUT"
