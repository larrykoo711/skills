#!/usr/bin/env bash
# stage-offline-apps.sh — stage offline app installers (ones you supply yourself)
# onto the target's Desktop with a bilingual HTML guide; the HUMAN installs them.
# Disk-image layouts (app vs nested dmg/pkg vs a separate installer) and Gatekeeper
# vary too much to auto-install reliably, so the reliable path is: deliver the files
# + a clear illustrated guide, then announce.
# Standard (single source of truth): standard/offline-apps.tsv.
#
# Source folder resolution: $1 → $MACOS_SETUP_LOCAL_PKGS → <skill>/.offline_apps.
# When the packages live on a network share, mount it first and point
# MACOS_SETUP_LOCAL_PKGS at the mount. Destination: $MACOS_SETUP_STAGE_DIR
# (default ~/Desktop/macos-setup-apps). MACOS_SETUP_SILENT=1 skips open/voice (tests).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

TSV="$SKILL_DIR/standard/offline-apps.tsv"
TPL="$SKILL_DIR/templates/offline-apps-guide.html"
PKG_DIR="${1:-${MACOS_SETUP_LOCAL_PKGS:-$SKILL_DIR/.offline_apps}}"
STAGE_DIR="${MACOS_SETUP_STAGE_DIR:-$HOME/Desktop/macos-setup-apps}"
# Preferred transport: pull straight from an SSH source via rsync, NOT a SMB mount.
# SMB over a high-latency mesh link (e.g. Tailscale) is slow — many round-trips per
# file. rsync over SSH streams + resumes and is far faster. Set
# MACOS_SETUP_PKG_SSH=<user@host:/path/to/dir> (the directory holding the .iso files).
PKG_SSH="${MACOS_SETUP_PKG_SSH:-}"

[ -f "$TSV" ] || { warn "no offline-apps standard ($TSV) — skipping offline installers"; exit 0; }
[ -f "$TPL" ] || { warn "no guide template ($TPL) — skipping offline installers"; exit 0; }
if [ -z "$PKG_SSH" ] && [ ! -d "$PKG_DIR" ]; then
  warn "no package source — set MACOS_SETUP_PKG_SSH=<user@host:path> (rsync over SSH, fast) or mount the share into MACOS_SETUP_LOCAL_PKGS"; exit 0
fi

mkdir -p "$STAGE_DIR"
msg "── staging offline installers → $STAGE_DIR ──"
present=0; missing=0; misslist=""
# rsync is idempotent (identical files skip) and resumable (--partial), so re-runs and
# aborted transfers cost no extra bandwidth. The SSH source reuses one connection
# (ControlMaster) so 9 files don't pay 9 handshakes.
SSH_OPTS="ssh -o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPath=/tmp/macos-setup-ssh-%r@%h:%p -o ControlPersist=120"
while IFS=$'\t' read -r file app _; do
  case "$file" in ''|\#*) continue ;; esac
  if [ -n "$PKG_SSH" ]; then
    if rsync -a --partial -e "$SSH_OPTS" "$PKG_SSH/$file" "$STAGE_DIR/" 2>/dev/null; then
      report_ok "staged $app ($file)"; present=$((present+1))
    else
      report_finding "staging copy failed over SSH: $file"
    fi
  elif [ -f "$PKG_DIR/$file" ]; then
    if rsync -a "$PKG_DIR/$file" "$STAGE_DIR/" 2>/dev/null; then
      report_ok "staged $app ($file)"; present=$((present+1))
    else
      report_finding "staging copy failed: $file"
    fi
  else
    warn "  missing in source: $file ($app)"; missing=$((missing+1)); misslist="$misslist $app"
  fi
done < "$TSV"

# ── render the bilingual guide from the same TSV (single source of truth) ──
GUIDE="$STAGE_DIR/安装说明.html"
HOST="$(scutil --get LocalHostName 2>/dev/null || hostname)"
# One generation path: gen-guide.py (standalone, also used to build the guide locally
# in any session and ship it ahead of the slow package transfer — see pitfalls #14).
if /usr/bin/python3 "$SCRIPT_DIR/gen-guide.py" "$TSV" "$TPL" "$GUIDE" "$HOST"; then
  report_ok "guide written: $GUIDE"
  # Archive the guide into the run's task dir, if one is active.
  [ -n "${MACOS_SETUP_TASK_DIR:-}" ] && [ -d "$MACOS_SETUP_TASK_DIR/artifacts" ] \
    && cp "$GUIDE" "$MACOS_SETUP_TASK_DIR/artifacts/install-guide.html" 2>/dev/null
else
  report_finding "failed to render the install guide (python3 / gen-guide.py?)"
fi

msg ""
msg "✅ staged $present installer(s) to $STAGE_DIR"
[ "$missing" -gt 0 ] && warn "missing from source ($missing):$misslist"

# ── ready: open the guide + folder and announce on the target (the human is here) ──
if [ "${MACOS_SETUP_SILENT:-0}" != "1" ]; then
  [ -f "$GUIDE" ] && open "$GUIDE" 2>/dev/null
  open "$STAGE_DIR" 2>/dev/null
  if [ "${MACOS_SETUP_NO_VOICE:-0}" != "1" ] && [ -x /usr/bin/say ]; then
    speak_audibly "$(msg_i18n offline_ready)" &
  fi
fi
