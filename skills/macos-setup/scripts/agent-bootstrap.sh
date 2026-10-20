#!/usr/bin/env bash
# agent-bootstrap.sh — Day-0 for a new agent-node: the one time a password is typed.
# A blank Mac has no key and no passwordless sudo, so nothing can be automated until
# a human authenticates once. This script does that once:
#   1. installs the operator's public key into ~/.ssh/authorized_keys (700/600)
#   2. installs a NOPASSWD sudoers drop-in — validated with `visudo -c` BEFORE install,
#      because a broken sudoers file locks sudo for everyone
# Prerequisite on the new Mac (TCC — no CLI can do it): Sharing → Remote Login ON,
# with "Allow full disk access for remote users".
#
# Usage:
#   agent-bootstrap.sh --pubkey <key.pub> --remote <user@host> [--jump <host>]
#       run it from the operator Mac: one SSH password + one sudo password, then
#       key login and passwordless sudo are verified
#   agent-bootstrap.sh --pubkey <key.pub> [--user <name>]
#       print the block to paste into Terminal ON the new Mac instead
set -eu
PUBKEY="" TUSER="${USER}" REMOTE="" JUMP=""
usage() { echo "usage: agent-bootstrap.sh --pubkey <key.pub> [--remote <user@host> [--jump <host>] | --user <name>]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pubkey) PUBKEY="$2"; shift 2 ;;
    --user)   TUSER="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --jump)   JUMP="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$PUBKEY" ] || { echo "public key file not found: ${PUBKEY:-<none>}" >&2; exit 2; }
KEY="$(head -1 "$PUBKEY")"
case "$KEY" in ssh-*|ecdsa-*|sk-*) ;; *) echo "not an OpenSSH public key: $PUBKEY" >&2; exit 2 ;; esac
case "$KEY" in *"'"*) echo "public key line contains a single quote — refusing to embed it" >&2; exit 2 ;; esac
# The account that gets passwordless sudo is the one SSH will actually log in as —
# user@host, else what ~/.ssh/config resolves for that host. Never this Mac's $USER by default.
if [ -n "$REMOTE" ]; then
  case "$REMOTE" in *@*) TUSER="${REMOTE%%@*}" ;; *) TUSER="$(ssh -G "$REMOTE" 2>/dev/null | awk '/^user /{print $2; exit}')" ;; esac
fi
case "$TUSER" in *[!a-zA-Z0-9._-]*|'') echo "invalid user name: ${TUSER:-<none>}" >&2; exit 2 ;; esac

# sudo's #includedir skips files whose name contains '.', so a dotted user name is mapped to '_'.
# Name shared with agent-ready.sh (SUDOERS_FILE) — keep in step.
SUDOERS="/etc/sudoers.d/macos-setup-$(printf '%s' "$TUSER" | tr . _)"

day0_block() {
  cat <<EOF
mkdir -p ~/.ssh && chmod 700 ~/.ssh && \\
{ grep -qxF '${KEY}' ~/.ssh/authorized_keys 2>/dev/null || echo '${KEY}' >> ~/.ssh/authorized_keys; } && \\
chmod 600 ~/.ssh/authorized_keys && \\
t=\$(mktemp) && echo '${TUSER} ALL=(ALL) NOPASSWD: ALL' > "\$t" && \\
sudo visudo -cf "\$t" && \\
sudo install -m 440 -o root -g wheel "\$t" ${SUDOERS} && \\
rm -f "\$t" && sudo -k && sudo -n true && echo "✅ day-0 done"
EOF
}

if [ -z "$REMOTE" ]; then
  echo "# ── on the new Mac, first: System Settings → General → Sharing → Remote Login: ON"
  echo "#    and tick \"Allow full disk access for remote users\". Then paste into Terminal: ──"
  day0_block
  exit 0
fi

[ -t 0 ] || { echo "--remote needs a terminal: you will type the SSH password and then the sudo password" >&2; exit 2; }
jump=(); [ -n "$JUMP" ] && jump=(-J "$JUMP")
PRIVKEY="${PUBKEY%.pub}"

echo "① SSH into $REMOTE with its login password (key auth is off for this one connection)…"
echo "   then sudo asks for the same password once."
# PubkeyAuthentication=no: an agent full of keys would hit "Too many authentication failures"
# before the password prompt. -t: sudo needs a tty to ask.
ssh -t ${jump[@]+"${jump[@]}"} -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new "$REMOTE" "$(day0_block)"

echo "② verifying key login + passwordless sudo (no password should be asked)…"
# shellcheck disable=SC2016  # $USER/$(…) expand on the target
if ssh ${jump[@]+"${jump[@]}"} -o BatchMode=yes -o IdentitiesOnly=yes -i "$PRIVKEY" "$REMOTE" \
     'sudo -n true && echo "   ✓ $(scutil --get LocalHostName): key login + NOPASSWD sudo for $USER"'; then
  echo "✅ day-0 complete — everything else runs remotely now (remote.sh)"
else
  echo "✗ verification failed — key login or sudo -n did not work; re-run, or paste the block on the Mac" >&2
  exit 1
fi
