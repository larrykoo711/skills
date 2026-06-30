#!/usr/bin/env bash
# sync-history.sh <host> <ssh-target> [date] — pull a remote run's history dir back into
# THIS machine's repo so the orchestrator keeps a durable, reviewable copy.
#
# Why this exists: in remote mode the skill is rsync'd to the target and task-init.sh
# builds .history/<host>/<date>-setup/ on the TARGET (under its $HOME, since the target
# has no repo). That copy is invisible to the operator driving the run from another Mac.
# This script rsyncs it back into the orchestrator's repo at .history/<host>/, which is
# the copy you review and keep long-term.
#
# Usage (from the skill dir, on the orchestrator):
#   bash scripts/sync-history.sh <host> <ssh-target>            # today's run
#   bash scripts/sync-history.sh <host> <ssh-target> 2026-01-15 # a specific run
#
# Idempotent and safe to re-run after each pipeline phase to keep the local copy fresh.
set -eu
HOST="${1:?usage: sync-history.sh <host> <ssh-target> [date]}"
TARGET="${2:?usage: sync-history.sh <host> <ssh-target> [date]}"
DATE="${3:-$(date '+%Y-%m-%d')}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root: walk up for a marker so this resolves whether invoked from the skill dir or
# the repo root. Override with MACOS_SETUP_HISTORY_ROOT.
ROOT="${MACOS_SETUP_HISTORY_ROOT:-}"
if [ -z "$ROOT" ]; then
  d="$SCRIPT_DIR"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    { [ -e "$d/.git" ] || [ -f "$d/fleet.yaml" ]; } && { ROOT="$d"; break; }
    d="$(dirname "$d")"
  done
  ROOT="${ROOT:-$PWD}"
fi

LOCAL_DIR="$ROOT/.history/$HOST/${DATE}-setup"
# The target's run dir: task-init.sh fell back to $HOME there (no repo marker), so it
# lives at ~/.history/<host>/<date>-setup. Resolve $HOME on the target, don't assume it.
REMOTE_HOME="$(ssh "$TARGET" 'printf %s "$HOME"')"
REMOTE_DIR="$REMOTE_HOME/.history/$HOST/${DATE}-setup"

mkdir -p "$LOCAL_DIR"
echo "↓ pulling $TARGET:$REMOTE_DIR/  →  $LOCAL_DIR/"
# raw/ can hold large collection dumps; keep them — they're the audit trail. --delete so
# the local copy mirrors the target (removed-on-target files don't linger locally).
rsync -a --delete "$TARGET:$REMOTE_DIR/" "$LOCAL_DIR/"
echo "✓ synced. Local history: $LOCAL_DIR"
ls -la "$LOCAL_DIR"
