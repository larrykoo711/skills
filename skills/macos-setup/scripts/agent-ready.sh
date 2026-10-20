#!/usr/bin/env bash
# agent-ready.sh — the Agent Device Ready layer (profile: agent-node).
# standard/agent-ready.tsv is the single source of truth; this file holds one
# check function per id (ar_<id>_check) and one apply function per auto id
# (ar_<id>_apply). tests/test_agent_ready.sh guards that the two stay in step.
#
# Usage: agent-ready.sh [--check | --apply | --list] [--only <id>]
#   --check (default)  read-only audit; exit 0 only when every item passes
#   --apply            fix auto items (each fix read back), then audit everything
#   --list             print the standard
#
# Verdicts — unknown is NEVER a pass:
#   pass    probed, compliant
#   fail    probed, not compliant (auto/check items)
#   manual  probed, not compliant, and only a human can fix it (sign-in, GUI login)
#   unknown could not be probed from here (e.g. needs an SSH session) — reported, not passed
# Set AGENT_READY_TSV=<path> to emit <verdict>TAB<id>TAB<en>TAB<zh> rows for reports.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/idempotent.sh
. "$SCRIPT_DIR/lib/idempotent.sh"

STD="$SKILL_DIR/standard/agent-ready.tsv"
MODE=check ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check; shift ;;
    --apply) MODE=apply; shift ;;
    --list)  MODE=list; shift ;;
    --only)  ONLY="${2:?--only needs an id}"; shift 2 ;;
    *) fail "unknown argument: $1"; exit 2 ;;
  esac
done

# Fixed names shared with agent-bootstrap.sh and the reference doc.
SUDOERS_FILE="/etc/sudoers.d/macos-setup-$(printf '%s' "$USER" | tr . _)"   # sudo skips dotted names in sudoers.d
SSHD_DROPIN="/etc/ssh/sshd_config.d/010-macos-setup-agent.conf"   # 010 < Apple's 100: first value wins
TMUX_LABEL="com.macos-setup.agent-tmux"
TMUX_SESSION="agent-home"
TS_LABEL="com.macos-setup.tailscale-login"
ORBCTL=/Applications/OrbStack.app/Contents/MacOS/bin/orbctl
# Optional: pin OrbStack's container subnet on every node (e.g. so it never collides with a LAN).
# Empty = leave OrbStack's default alone.
ORB_SUBNET4="${AGENT_ORBSTACK_SUBNET4:-}"
# Where the 1Password Service Account token lives (written once by a human, mode 600).
OP_TOKEN_FILE="${AGENT_OP_TOKEN_FILE:-$HOME/.config/agent-secrets/op-sa.token}"
BREW_PREFIX="$( [ -x /opt/homebrew/bin/brew ] && echo /opt/homebrew || echo /usr/local )"
AGENT_PATH="$HOME/.local/bin:$HOME/.local/share/fnm/aliases/default/bin:$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$HOME/.orbstack/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$AGENT_PATH:$PATH"

over_ssh() { [ -n "${SSH_CONNECTION:-}" ]; }
# bounded <secs> <cmd…> — macOS has no timeout(1); perl's alarm is always there.
# A probe that hangs (an app's CLI before its first launch) must end as a verdict, not a stall.
bounded() { local s="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
need_sudo() {
  sudo -n true 2>/dev/null && return 0
  [ -t 0 ] && sudo -v && return 0
  report_finding "sudo needed and not available non-interactively — run agent-bootstrap first"
  return 1
}
pmset_val() { pmset -g 2>/dev/null | awk -v k="$1" '$1==k{print $2; exit}'; }

# in_gui <cmd…> — run a command inside the GUI-session tmux server and return its
# exit code. Keychain-backed tools (claude, gh) only work there when we arrived over
# SSH; probing them from the SSH shell gives false negatives. 99 = no GUI server.
in_gui() {
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null || return 99
  local rc_file; rc_file="$(mktemp -t agent-ready)"
  # bounded: a keychain prompt nobody answers would otherwise block run-shell forever
  tmux run-shell -t "$TMUX_SESSION" "PATH='$AGENT_PATH'; perl -e 'alarm 25; exec @ARGV' $* >/dev/null 2>&1 </dev/null; echo \$? > '$rc_file'"
  local rc; rc="$(cat "$rc_file" 2>/dev/null)"; rm -f "$rc_file"
  return "${rc:-98}"
}
# keychain_probe <cmd…> — 0 pass / 1 fail / 2 unknown, choosing the right context.
keychain_probe() {
  in_gui "$@"; local rc=$?
  [ "$rc" -eq 99 ] || { [ "$rc" -eq 0 ] && return 0 || return 1; }
  bounded 20 "$@" >/dev/null 2>&1 && return 0
  over_ssh && return 2      # SSH can't read the login keychain: absence proves nothing
  return 1
}

# ═══ reach ═══════════════════════════════════════════════════════════
ar_ssh_remote_login_check() { launchctl print-disabled system 2>/dev/null | grep -q '"com.openssh.sshd" => enabled'; }
ar_ssh_remote_login_apply() {
  need_sudo || return 1
  sudo systemsetup -f -setremotelogin on >/dev/null 2>&1 \
    || { sudo launchctl enable system/com.openssh.sshd && sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null; }
}

ar_ssh_authorized_key_check() {
  local ak="$HOME/.ssh/authorized_keys"
  [ -s "$ak" ] && [ "$(stat -f %Lp "$HOME/.ssh")" = 700 ] && [ "$(stat -f %Lp "$ak")" = 600 ] \
    && grep -qE '(^|[ ,"])(ssh-|ecdsa-|sk-)[a-z0-9@.-]+ AAAA' "$ak"
}
# Is the current SSH session itself authenticated by a public key? (sshd logs it per connection;
# ExposeAuthInfo is off by default, so ask the unified log.) Unknown → don't lock the door.
session_used_pubkey() {
  over_ssh || return 1
  # Some Macs don't log sshd's "Accepted publickey". The orchestrator can prove key login
  # instead: `ssh -o PreferredAuthentications=publickey -o BatchMode=yes <host> true` succeeded,
  # then it re-applies with AR_PUBKEY_VERIFIED=1 (remote.sh-style callers only).
  [ "${AR_PUBKEY_VERIFIED:-}" = 1 ] && return 0
  local port; port="$(printf '%s' "$SSH_CONNECTION" | awk '{print $2}')"
  sudo -n log show --last 2h --style compact --predicate 'process == "sshd-session" OR process == "sshd"' 2>/dev/null \
    | grep -q "Accepted publickey .* port ${port} "
}

ar_ssh_key_only_check() {
  sudo -n true 2>/dev/null || return 2
  local t; t="$(sudo sshd -T 2>/dev/null)"
  printf '%s\n' "$t" | grep -qx 'passwordauthentication no' \
    && printf '%s\n' "$t" | grep -qx 'kbdinteractiveauthentication no'
}
ar_ssh_key_only_apply() {
  # Never lock the door before the key is in it.
  ar_ssh_authorized_key_check || { report_finding "ssh-key-only skipped: no valid authorized_keys yet (would lock you out)"; return 1; }
  # A key in the file is not proof the operator's key works: require this very session to have
  # logged in by key. Applied from the console (not over SSH) it is left to a human.
  session_used_pubkey || { report_finding "ssh-key-only skipped: this session did not log in with a key (or cannot be verified) — log in with your key, then re-apply"; return 1; }
  need_sudo || return 1
  printf '# managed by macos-setup agent-ready — key-only SSH\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
    | sudo tee "$SSHD_DROPIN" >/dev/null
  sudo sshd -t 2>/dev/null || { sudo rm -f "$SSHD_DROPIN"; report_finding "sshd -t rejected the drop-in — removed it"; return 1; }
}

ar_sudo_nopasswd_check() { sudo -n true 2>/dev/null; }
ar_sudo_nopasswd_apply() {
  [ -t 0 ] || { report_finding "sudo-nopasswd needs the password once — run agent-bootstrap on the machine"; return 1; }
  local tmp; tmp="$(mktemp)"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USER" > "$tmp"
  # Validate before install: a broken sudoers file locks sudo for everyone.
  sudo visudo -cf "$tmp" >/dev/null && sudo install -m 440 -o root -g wheel "$tmp" "$SUDOERS_FILE"
  local rc=$?; rm -f "$tmp"; sudo -k; return $rc
}

ar_remote_fda_check() {
  over_ssh || return 2      # only an SSH session can tell what SSH sessions may read
  head -c 1 "/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1
}

ar_noninteractive_path_check() {
  # Exactly what sshd hands a non-interactive command: minimal PATH, zsh reads only zshenv.
  local miss
  miss="$(env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /bin/zsh -c 'for b in brew git tmux claude node npx; do command -v $b >/dev/null || printf "%s " $b; done' 2>/dev/null)"
  [ -z "$miss" ] || { AR_NOTE="missing: ${miss}— add their dirs to PATH in ~/.zshenv"; return 1; }
}

ar_tailscale_up_check() {
  local ts; ts="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
  [ -x "$ts" ] || { AR_NOTE="Tailscale not installed"; return 1; }
  local out; out="$(bounded 10 "$ts" status --json 2>/dev/null)"
  [ $? -eq 142 ] && { AR_NOTE="Tailscale CLI not answering — open Tailscale.app once and sign in"; return 1; }
  printf '%s' "$out" | grep -q '"BackendState": *"Running"'
}

# ═══ always-on ═══════════════════════════════════════════════════════
ar_power_never_sleep_check() { [ "$(pmset_val sleep)" = 0 ] && [ "$(pmset_val disksleep)" = 0 ]; }
ar_power_never_sleep_apply() { need_sudo && sudo pmset -a sleep 0 disksleep 0; }

ar_power_autorestart_check() {
  local v; v="$(pmset_val autorestart)"
  [ -n "$v" ] || return 2   # laptops don't expose it: not probed ≠ off
  [ "$v" = 1 ]
}
ar_power_autorestart_apply() { need_sudo && sudo pmset -a autorestart 1; }

ar_power_womp_check() {
  local v; v="$(pmset_val womp)"
  [ -n "$v" ] || return 2   # not offered on this model: not probed ≠ off
  [ "$v" = 1 ]
}
ar_power_womp_apply() { need_sudo && sudo pmset -a womp 1; }

SU_PLIST=/Library/Preferences/com.apple.SoftwareUpdate
ar_updates_no_surprise_reboot_check() { [ "$(defaults read "$SU_PLIST" AutomaticallyInstallMacOSUpdates 2>/dev/null)" = 0 ]; }
ar_updates_no_surprise_reboot_apply() {
  need_sudo || return 1
  sudo defaults write "$SU_PLIST" AutomaticallyInstallMacOSUpdates -bool false
  sudo defaults write "$SU_PLIST" CriticalUpdateInstall -bool true   # keep security responses
}

ar_filevault_unattended_check() {
  fdesetup status 2>/dev/null | grep -q "FileVault is Off" && { AR_NOTE="FileVault off"; return 0; }
  # macOS 26+ on Apple Silicon unlocks FileVault over SSH at pre-boot — needs Remote Login.
  if [ "$(uname -m)" = arm64 ] && [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ] && ar_ssh_remote_login_check; then
    AR_NOTE="FileVault on — after a reboot: ssh in once to unlock (pre-boot host key differs), then reconnect; planned reboots: sudo fdesetup authrestart"
    return 0
  fi
  AR_NOTE="FileVault on and no SSH pre-boot unlock — a reboot waits for a human"; return 1
}

ar_gui_session_check() { [ "$(stat -f %Su /dev/console 2>/dev/null)" = "$USER" ]; }

ar_tmux_gui_server_check() {
  launchctl print "gui/$(id -u)/$TMUX_LABEL" >/dev/null 2>&1 && tmux has-session -t "$TMUX_SESSION" 2>/dev/null
}
# launch_agent <label> <keepalive:true|false> <program> [args…] — write, (re)load, done.
# One writer for every agent the profile owns, so they all share PATH, logging and reload.
launch_agent() {
  local label="$1" keep="$2"; shift 2
  local plist="$HOME/Library/LaunchAgents/${label}.plist" args="" a
  for a in "$@"; do args="${args}<string>$(printf '%s' "$a" | sed 's/&/\&amp;/g; s/</\&lt;/g')</string>"; done
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array>${args}</array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>${AGENT_PATH}</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><${keep}/>
  <key>AbandonProcessGroup</key><true/>
  <key>StandardErrorPath</key><string>/tmp/${label}.log</string>
</dict></plist>
PLIST
  plutil -lint "$plist" >/dev/null || { report_finding "invalid plist written: $plist"; return 1; }
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$plist" && sleep 2
}
agent_loaded() { launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1; }

ar_tmux_gui_server_apply() {
  ar_gui_session_check || { report_finding "tmux-gui-server needs a console login first (gui-session)"; return 1; }
  local tmux_bin; tmux_bin="$(command -v tmux)" || { report_finding "tmux not installed"; return 1; }
  launch_agent "$TMUX_LABEL" false "$tmux_bin" new-session -A -d -s "$TMUX_SESSION"
}

# Tailscale's own "launch at login" toggle can disagree with System Settings after a
# cask rename/reinstall (SMAppService registration goes stale). Own it with a LaunchAgent:
# `open` on a running app is a no-op, so it coexists with the toggle if that ever works.
ar_tailscale_at_login_check() { agent_loaded "$TS_LABEL"; }
ar_tailscale_at_login_apply() {
  [ -d /Applications/Tailscale.app ] || { report_finding "Tailscale.app not installed"; return 1; }
  launch_agent "$TS_LABEL" false /usr/bin/open -g -a /Applications/Tailscale.app
}

orb_get() { bounded 10 "$ORBCTL" config show 2>/dev/null | awk -v k="$1:" '$1==k{print $2}'; }
ar_orbstack_agent_config_check() {
  [ -x "$ORBCTL" ] || { AR_NOTE="OrbStack not installed"; return 1; }
  local miss=""
  [ "$(orb_get app.start_at_login)" = true ] || miss="${miss}start_at_login "
  [ "$(orb_get k8s.enable)" = false ]       || miss="${miss}k8s-off "
  [ -z "$ORB_SUBNET4" ] || [ "$(orb_get network.subnet4)" = "$ORB_SUBNET4" ] || miss="${miss}subnet4 "
  # The config is not the state: `config set` applies only after OrbStack restarts, so a
  # config-only check passed while k8s pods were still running (seen on a first checkup).
  [ -z "$(orb_k8s_running)" ] || miss="${miss}k8s-still-running(restart-pending) "
  [ -z "$miss" ] || { AR_NOTE="differs: ${miss}"; return 1; }
}
orb_k8s_running() { bounded 15 docker ps -q --filter name=^k8s_ 2>/dev/null; }
ar_orbstack_agent_config_apply() {
  [ -x "$ORBCTL" ] || return 1
  bounded 20 "$ORBCTL" config set app.start_at_login true
  bounded 20 "$ORBCTL" config set k8s.enable false
  local subnet_before; subnet_before="$(orb_get network.subnet4)"
  [ -z "$ORB_SUBNET4" ] || bounded 20 "$ORBCTL" config set network.subnet4 "$ORB_SUBNET4"
  # Settings take effect on restart. Restart only when the running state disagrees (k8s still
  # up, or the subnet just changed) — it stops every container, so never as a reflex.
  if [ -n "$(orb_k8s_running)" ] || { [ -n "$ORB_SUBNET4" ] && [ "$subnet_before" != "$ORB_SUBNET4" ]; }; then
    msg "  restarting OrbStack to apply its config (running containers will stop)"
    bounded 60 "$ORBCTL" stop && bounded 120 "$ORBCTL" start
  fi
}

# ═══ toolchain ═══════════════════════════════════════════════════════
ar_claude_auth_check() { have claude || { AR_NOTE="claude not installed"; return 1; }; keychain_probe claude auth status; }
ar_gh_auth_check()     { have gh || { AR_NOTE="gh not installed"; return 1; }; keychain_probe gh auth status; }
ar_git_identity_check() { [ -n "$(git config --global user.name)" ] && [ -n "$(git config --global user.email)" ]; }
# 1Password for agents = a Service Account token (never the desktop app: it prompts per
# terminal session and is invisible from launchd-started process trees).
ar_op_service_account_check() {
  have op || { AR_NOTE="1Password CLI (op) not installed"; return 1; }
  [ -s "$OP_TOKEN_FILE" ] || { AR_NOTE="no token at $OP_TOKEN_FILE"; return 1; }
  [ "$(stat -f %Lp "$OP_TOKEN_FILE")" = 600 ] || { AR_NOTE="$OP_TOKEN_FILE must be mode 600"; return 1; }
  OP_SERVICE_ACCOUNT_TOKEN="$(cat "$OP_TOKEN_FILE")" bounded 30 op whoami >/dev/null 2>&1 \
    || { AR_NOTE="op whoami fails with the token at $OP_TOKEN_FILE"; return 1; }
}
ar_docker_ready_check() { have docker || { AR_NOTE="docker CLI not on PATH (OrbStack)"; return 1; }; bounded 15 docker info >/dev/null 2>&1; }

# ═══ driver ══════════════════════════════════════════════════════════
PASS=0 FAIL=0 MANUAL=0 UNKNOWN=0
[ -n "${AGENT_READY_TSV:-}" ] && : > "$AGENT_READY_TSV"
fn_of() { printf 'ar_%s' "$(printf '%s' "$1" | tr '-' '_')"; }

record() {  # <verdict> <id> <en> <zh>
  local note="${AR_NOTE:+ — $AR_NOTE}"
  case "$1" in
    pass)    PASS=$((PASS+1));       report_ok "[agent-ready] $2: $3$note" ;;
    fail)    FAIL=$((FAIL+1));       report_finding "[agent-ready] $2: $3$note" ;;
    manual)  MANUAL=$((MANUAL+1));   report_finding "[agent-ready][MANUAL] $2: $3$note" ;;
    unknown) UNKNOWN=$((UNKNOWN+1)); warn "[agent-ready][UNKNOWN] $2: $3$note — not probed from here, not a pass" ;;
  esac
  [ -n "${AGENT_READY_TSV:-}" ] && printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$AGENT_READY_TSV"
  return 0
}

if [ "$MODE" = list ]; then
  grep -vE '^\s*(#|$)' "$STD" | awk -F'\t' '{printf "%-28s %-10s %-7s %s\n", $1, $2, $3, $4}'
  exit 0
fi

msg "════ agent-ready ${MODE} @ $(scutil --get LocalHostName 2>/dev/null) ════"
mkdir -p "$(dirname "$FINDINGS_FILE")" 2>/dev/null
SEEN=0
while IFS=$'\t' read -r id _layer mode en zh <&3; do
  [ -n "$ONLY" ] && [ "$id" != "$ONLY" ] && continue
  cfg_excluded "agent:$id" && { msg "  skip $id (rejected by user)"; continue; }
  SEEN=$((SEEN+1))
  f="$(fn_of "$id")"
  AR_NOTE=""
  "${f}_check" </dev/null; rc=$?
  if [ "$rc" -ne 0 ] && [ "$MODE" = apply ] && [ "$mode" = auto ]; then
    msg "  → applying $id"
    "${f}_apply" </dev/null
    AR_NOTE=""; "${f}_check" </dev/null; rc=$?          # read back — an unverified write doesn't count
  fi
  case "$rc" in
    0) record pass "$id" "$en" "$zh" ;;
    2) record unknown "$id" "$en" "$zh" ;;
    *) if [ "$mode" = manual ]; then record manual "$id" "$en" "$zh"; else record fail "$id" "$en" "$zh"; fi ;;
  esac
done 3< <(grep -vE '^\s*(#|$)' "$STD")

# Every row must have been looked at — a typo'd --only, or a probe that swallowed the list,
# must not end as an all-green zero.
if [ -n "$ONLY" ] && [ "$SEEN" -eq 0 ]; then fail "no such id: $ONLY (see --list)"; exit 2; fi
want_rows="$(grep -cvE '^\s*(#|$)' "$STD")"
if [ -z "$ONLY" ] && [ "$SEEN" -ne "$want_rows" ]; then fail "only $SEEN of $want_rows items were evaluated"; exit 2; fi

msg "════ agent-ready: ${PASS} pass · ${FAIL} fail · ${MANUAL} manual · ${UNKNOWN} unknown ════"
[ $((FAIL + MANUAL + UNKNOWN)) -eq 0 ]
