#!/usr/bin/env bash
# remote.sh — drive any macos-setup step on another Mac from this one.
# Replaces the hand-typed "rsync → ssh -t → tmux → sync-history" dance with one
# command, so an agent can orchestrate a whole setup without a human at either end.
#
#   remote.sh <host> <ssh-target> <step> [args…]   run scripts/<step>.sh on the target
#   remote.sh <host> <ssh-target> --status         is the run still going? tail its log
#
# What it does for a step:
#   1. rsync this skill to <ssh-target>:/tmp/macos-setup/ (fresh copy every run)
#   2. run the step detached with nohup on the target (survives SSH drops; needs no tmux,
#      so it works on a blank Mac), with MACOS_SETUP_TASK_DIR from task-init.sh and
#      MACOS_SETUP_SILENT=1
#      under `caffeinate -i` — a fresh Mac idle-sleeps after ~10 min, and a background
#      brew download is not "user activity", so without it the target falls asleep mid-run
#   3. wait for it, print the log tail and the step's real exit code
#   4. pull the run record back with sync-history.sh
# Steps that ask y/N (cleanup.sh) need a human: run them with `ssh -t <target> bash /tmp/macos-setup/scripts/cleanup.sh`.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST="${1:?usage: remote.sh <host> <ssh-target> <step|--status> [args…]}"
TARGET="${2:?usage: remote.sh <host> <ssh-target> <step|--status> [args…]}"
STEP="${3:?usage: remote.sh <host> <ssh-target> <step|--status> [args…]}"
shift 3
RDIR=/tmp/macos-setup
LOCK="/tmp/macos-setup-remote.lock"          # a directory: mkdir is atomic; holds the run's pid
LOG="/tmp/macos-setup-remote.log"
RC_FILE="/tmp/macos-setup-remote.rc"
TASK_FILE="/tmp/macos-setup-remote.taskdir"  # the run dir name, so history sync uses the TARGET's date
# Non-interactive SSH loads no profile — name the PATH explicitly or tools read as missing.
RPATH='$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.orbstack/bin:/usr/bin:/bin:/usr/sbin:/sbin'

# Shell snippet evaluated on the target. running: the lock exists and either its pid is alive,
# or it is still being set up (no pid yet, under 10 min old). A lock whose pid is dead is stale.
RUNNING='running() { [ -d '"$LOCK"' ] || return 1; if [ -f '"$LOCK"'/pid ]; then kill -0 "$(cat '"$LOCK"'/pid)" 2>/dev/null && return 0; rm -rf '"$LOCK"'; return 1; fi; [ -n "$(find '"$LOCK"' -maxdepth 0 -mmin -10)" ]; }; if'
status() {
  # shellcheck disable=SC2029  # LOG/RC_FILE expand locally on purpose
  ssh "$TARGET" "$RUNNING running; then echo '● running'; else echo '○ idle'; fi; \
    [ -f $RC_FILE ] && echo \"last exit: \$(cat $RC_FILE)\"; tail -n 25 $LOG 2>/dev/null"
}
[ "$STEP" = "--status" ] && { status; exit 0; }

[ -f "$SCRIPT_DIR/$STEP.sh" ] || { echo "no such step: scripts/$STEP.sh" >&2; exit 2; }
ssh -o ConnectTimeout=8 "$TARGET" true || { echo "cannot reach $TARGET over SSH" >&2; exit 2; }
# Take the lock BEFORE touching the target's copy of the skill: a second remote.sh must not
# rsync --delete the scripts a first one is running.
# shellcheck disable=SC2029
ssh "$TARGET" "$RUNNING running; then exit 3; fi; mkdir $LOCK 2>/dev/null || exit 3"; r=$?
case "$r" in
  0) ;;
  3) echo "a macos-setup run is already in progress on $TARGET — check it: remote.sh $HOST $TARGET --status" >&2; exit 2 ;;
  *) echo "cannot reach $TARGET to take the run lock" >&2; exit 2 ;;
esac
release() { ssh "$TARGET" "rm -rf $LOCK" 2>/dev/null; }

echo "→ syncing skill to $TARGET:$RDIR/"
rsync -a --delete --exclude .history "$SKILL_DIR/" "$TARGET:$RDIR/" \
  || { echo "rsync to $TARGET failed — refusing to run a stale copy" >&2; release; exit 2; }

args=""; for a in "$@"; do args="$args $(printf '%q' "$a")"; done
inner="export PATH=$RPATH; cd $RDIR && export MACOS_SETUP_SILENT=1 MACOS_SETUP_TASK_DIR=\$(bash scripts/task-init.sh $HOST); \
basename \"\$MACOS_SETUP_TASK_DIR\" > $TASK_FILE; \
caffeinate -i bash scripts/$STEP.sh$args 2>&1 | tee $LOG; echo \${PIPESTATUS[0]} > $RC_FILE; rm -rf $LOCK"
echo "→ running $STEP on $TARGET (detached; log $LOG)"
# shellcheck disable=SC2029
ssh "$TARGET" "rm -f $RC_FILE $TASK_FILE; nohup bash -c $(printf '%q' "$inner") >/dev/null 2>&1 </dev/null & echo \$! > $LOCK/pid" \
  || { echo "could not start $STEP on $TARGET" >&2; release; exit 2; }

# Poll. ssh exit 255 = we could not ask (target asleep / off the network) — that is not
# "finished": keep waiting, and give up loudly after ~10 minutes of silence.
lost=0
while :; do
  # shellcheck disable=SC2029
  ssh -o ConnectTimeout=8 "$TARGET" "$RUNNING running; then exit 0; else exit 1; fi"; r=$?
  case "$r" in
    0) lost=0 ;;
    1) break ;;
    *) lost=$((lost+1))
       [ "$lost" -eq 1 ] && echo "… $TARGET not answering (asleep? off Wi-Fi?) — still waiting" >&2
       [ "$lost" -ge 60 ] && { echo "✗ lost $TARGET for 10 min — the step may still be running there; check later: remote.sh $HOST $TARGET --status" >&2; exit 2; } ;;
  esac
  sleep 10
done
rc="$(ssh "$TARGET" "cat $RC_FILE 2>/dev/null")"
ssh "$TARGET" "tail -n 40 $LOG"
echo "← $STEP exit ${rc:-unknown}"
run_dir="$(ssh "$TARGET" "cat $TASK_FILE 2>/dev/null")"
if bash "$SCRIPT_DIR/sync-history.sh" "$HOST" "$TARGET" "${run_dir%-setup}" >/dev/null 2>&1; then
  echo "← run record synced to .history/$HOST/${run_dir}"
else
  echo "⚠ run record NOT synced (sync-history.sh $HOST $TARGET ${run_dir%-setup})" >&2
fi
case "$rc" in ''|*[!0-9]*) exit 2 ;; *) exit "$rc" ;; esac
