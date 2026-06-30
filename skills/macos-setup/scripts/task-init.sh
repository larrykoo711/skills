#!/usr/bin/env bash
# task-init.sh [host] — create the run directory for one macos-setup run and seed the
# README / TIMELINE / CHANGELOG / REPORT docs from templates/task/. Idempotent: existing
# docs are kept (so re-running mid-task never clobbers your notes). Prints the run dir
# path on stdout so callers can do: TASK_DIR="$(bash task-init.sh <host>)".
#
# Layout (gitignored — see .gitignore):
#   .history/<host>/<YYYY-MM-DD>-setup/
#     README.md TIMELINE.md CHANGELOG.md REPORT.md  artifacts/  raw/
# One directory per device per run — a device's setup history lives next to its other
# records and travels with the device. Every other macos-setup script writes its outputs
# under this dir (artifacts/ for HTML/order-sheet/exclude/guide, raw/ for
# precheck/collect/findings/logs) instead of scattering them across /tmp and the Desktop.
#
# Remote runs: the skill is rsync'd to the target, so this script builds the run dir on
# the *target*. The orchestrator then rsyncs it back into its own repo's
# .history/<host>/ via sync-history.sh — that is the durable, reviewable copy.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SCRIPT_DIR/../templates/task"
# History root: walk up for a marker (.git / fleet.yaml) so this works whether the skill
# lives inside the repo or was rsync'd to /tmp on a target machine. A bare 4-level
# "../../../.." breaks the moment the skill isn't at .claude/skills/macos-setup/scripts.
# Override with MACOS_SETUP_HISTORY_ROOT (legacy: MACOS_SETUP_TASK_ROOT); fall back to
# $HOME when no marker is found.
ROOT="${MACOS_SETUP_HISTORY_ROOT:-${MACOS_SETUP_TASK_ROOT:-}}"
if [ -z "$ROOT" ]; then
  d="$SCRIPT_DIR"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    { [ -e "$d/.git" ] || [ -f "$d/fleet.yaml" ]; } && { ROOT="$d"; break; }
    d="$(dirname "$d")"
  done
  ROOT="${ROOT:-$HOME}"
fi

HOST="${1:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
DATE="$(date '+%Y-%m-%d')"
NOW="$(date '+%Y-%m-%d %H:%M')"
TASK_DIR="$ROOT/.history/${HOST}/${DATE}-setup"

mkdir -p "$TASK_DIR/artifacts" "$TASK_DIR/raw"
for f in README TIMELINE CHANGELOG REPORT; do
  [ -f "$TASK_DIR/$f.md" ] && continue                 # never clobber existing notes
  if [ -f "$TPL/$f.md" ]; then
    sed -e "s/{{HOST}}/$HOST/g" -e "s/{{DATE}}/$NOW/g" "$TPL/$f.md" > "$TASK_DIR/$f.md"
  fi
done
echo "$TASK_DIR"
