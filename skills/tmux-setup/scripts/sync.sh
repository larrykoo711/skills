#!/usr/bin/env bash
# sync.sh — tmux standard sync script
#
# Purpose: first-time deploy + later upgrades all go through this one script
# Features:
#   - auto-detects install state, installs only missing dependencies
#   - shows a diff before pushing, confirms file by file
#   - idempotent: safe to run multiple times
#   - supports macOS / Ubuntu / OpenWrt
#   - prints a confirmation message after testing SSH connectivity
#
# Usage:
#   ./sync.sh                    # interactively select machines
#   ./sync.sh workstation        # target a single host by id
#   ./sync.sh web1 web2          # multiple hosts
#   ./sync.sh --all              # all deployable machines
#   ./sync.sh --dry-run          # only show diffs, do not execute
#
# Machine inventory is read from devices.conf (see devices.example.conf).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL_DIR="$SKILL_DIR/templates"
SSH_KEY="${TMUX_SETUP_SSH_KEY:-$HOME/.ssh/id_ed25519}"

# ── Machine inventory (host_id|platform|ssh_user|ssh_host|display_name) ──
# platform: macos | ubuntu | openwrt | local (this machine, operated directly)
# Loaded from $SKILL_DIR/devices.conf at startup (see load_devices below).
DEVICES=()

# ── Load inventory from devices.conf ────────────────────────────────────
load_devices() {
  local conf="$SKILL_DIR/devices.conf"
  if [[ ! -f "$conf" ]]; then
    echo "❌ Inventory not found: $conf"
    echo ""
    echo "  Create it from the example template, then list your own machines:"
    echo "    cp $SKILL_DIR/devices.example.conf $conf"
    echo "    \$EDITOR $conf"
    echo ""
    echo "  Format (one machine per line, five pipe-separated fields):"
    echo "    host_id | platform | ssh_user | ssh_host | display_name"
    exit 1
  fi

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    DEVICES+=("$line")
  done < "$conf"

  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    echo "❌ No machines defined in $conf"
    echo "  Add at least one machine, then re-run."
    exit 1
  fi
}

# ── Global flags ────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false       # skip diff confirmation, overwrite directly (for CI/cron)

# ── SSH helper functions ──────────────────────────────────────────────────
ssh_opts() {
  echo -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes
}

run_remote() {
  local user="$1" host="$2"; shift 2
  # shellcheck disable=SC2046
  ssh $(ssh_opts) "${user}@${host}" "$@"
}

scp_push() {
  local src="$1" user="$2" host="$3" dst="$4"
  # shellcheck disable=SC2046
  scp $(ssh_opts) "$src" "${user}@${host}:${dst}"
}

# ── Device lookup ──────────────────────────────────────────────────────────
find_device() {
  local target="$1"
  for dev in "${DEVICES[@]}"; do
    IFS='|' read -r hid _ _ _ _ <<< "$dev"
    [[ "$hid" == "$target" ]] && { echo "$dev"; return 0; }
  done
  return 1
}

# ── Connectivity test ──────────────────────────────────────────────────────
test_ssh() {
  local user="$1" host="$2" hid="$3"
  echo -n "  Testing SSH connectivity... "
  if run_remote "$user" "$host" "echo 'ok'" >/dev/null 2>&1; then
    echo "✓"
    return 0
  else
    echo "✗ cannot connect to ${user}@${host}"
    return 1
  fi
}

# ── Detect status ──────────────────────────────────────────────────────────
detect_status() {
  local user="$1" host="$2" platform="$3" hid="$4"
  echo "  ── Current state ──"

  local tmux_ver fzf_ver tmuxinator_ver t_cli zshrc_ok
  tmux_ver=$(run_remote "$user" "$host" "tmux -V 2>/dev/null | awk '{print \$2}'" 2>/dev/null || echo "")
  t_cli=$(run_remote "$user" "$host" "test -f ~/.zsh/t.zsh && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
  zshrc_ok=$(run_remote "$user" "$host" "grep -q 't.zsh' ~/.zshrc 2>/dev/null && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

  [[ -n "$tmux_ver" ]] && echo "  tmux: ✓ $tmux_ver" || echo "  tmux: ✗ not installed"

  if [[ "$platform" == "macos" || "$platform" == "ubuntu" ]]; then
    fzf_ver=$(run_remote "$user" "$host" "fzf --version 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "")
    tmuxinator_ver=$(run_remote "$user" "$host" "tmuxinator version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true" 2>/dev/null || echo "")
    local sesh_ver
    sesh_ver=$(run_remote "$user" "$host" "sesh --version 2>/dev/null | head -1 || true" 2>/dev/null || echo "")
    [[ -n "$fzf_ver" ]]        && echo "  fzf: ✓ $fzf_ver"          || echo "  fzf: ✗ not installed"
    [[ -n "$tmuxinator_ver" ]] && echo "  tmuxinator: ✓ $tmuxinator_ver" || echo "  tmuxinator: ✗ not installed"
    [[ -n "$sesh_ver" ]]       && echo "  sesh: ✓ ${sesh_ver}"      || echo "  sesh: ✗ not installed (optional)"
  fi

  [[ "$t_cli" == "yes" ]]    && echo "  t CLI: ✓ installed" || echo "  t CLI: ✗ not configured"
  [[ "$zshrc_ok" == "yes" ]] && echo "  .zshrc source: ✓" || echo "  .zshrc source: ✗ not configured"

  if [[ "$platform" == "macos" || "$platform" == "ubuntu" ]]; then
    local yml_count
    yml_count=$(run_remote "$user" "$host" "ls ~/.config/tmuxinator/*.yml 2>/dev/null | wc -l | tr -d ' '" 2>/dev/null || echo "0")
    echo "  tmuxinator templates: ${yml_count}"
  fi
}

# ── Install dependencies ──────────────────────────────────────────────────
install_deps() {
  local user="$1" host="$2" platform="$3"
  $DRY_RUN && { echo "  [dry-run] skipping dependency install"; return 0; }

  echo "→ Installing dependencies ($platform)..."

  if [[ "$platform" == "macos" ]]; then
    # macOS best practice:
    #   1. brew install tmux fzf zoxide (official tap)
    #   2. brew install ruby to use brew ruby (not macOS system ruby 2.6)
    #   3. brew ruby gem install tmuxinator (into <brew-prefix>/lib/ruby/gems/X/bin/)
    #   4. add gem bin to PATH (idempotent write to ~/.zshrc)
    #   5. sesh optional (brew tap joshmedeski/sesh)
    # brew prefix: /opt/homebrew on Apple Silicon, /usr/local on Intel.
    run_remote "$user" "$host" 'bash' << 'REMOTE'
set -e
# Locate brew across Apple Silicon (/opt/homebrew) and Intel (/usr/local).
if [ -x /opt/homebrew/bin/brew ]; then
  export PATH="/opt/homebrew/bin:$PATH"
elif [ -x /usr/local/bin/brew ]; then
  export PATH="/usr/local/bin:$PATH"
fi
command -v brew >/dev/null 2>&1 || { echo "ERROR: brew not found (checked /opt/homebrew and /usr/local)"; exit 1; }

# Base tools
command -v tmux   >/dev/null 2>&1 || brew install tmux
command -v fzf    >/dev/null 2>&1 || brew install fzf
command -v zoxide >/dev/null 2>&1 || brew install zoxide

# brew ruby (>= 3.x; system ruby 2.6 cannot write gems to /Library)
brew list ruby >/dev/null 2>&1 || brew install ruby

BREW_RUBY_BIN="$(brew --prefix ruby)/bin"
BREW_GEM_BIN="$(${BREW_RUBY_BIN}/gem env gemdir 2>/dev/null)/bin"
export PATH="${BREW_GEM_BIN}:${BREW_RUBY_BIN}:$PATH"

command -v tmuxinator >/dev/null 2>&1 || \
  "${BREW_RUBY_BIN}/gem" install tmuxinator --no-document

# Idempotent PATH write to ~/.zshrc
if ! grep -qF "BREW_GEM_PATH_INIT" ~/.zshrc 2>/dev/null; then
  cat >> ~/.zshrc << 'ZSHBLOCK'
# BREW_GEM_PATH_INIT — brew ruby gem bins (tmuxinator etc.)
_brew_ruby_bin="$(brew --prefix ruby 2>/dev/null)/bin"
_brew_gem_bin="$( ${_brew_ruby_bin}/gem env gemdir 2>/dev/null )/bin"
export PATH="${_brew_gem_bin}:${_brew_ruby_bin}:$PATH"
unset _brew_ruby_bin _brew_gem_bin
ZSHBLOCK
fi

# sesh (optional)
command -v sesh >/dev/null 2>&1 || \
  brew install joshmedeski/sesh/sesh 2>/dev/null || true

echo "✓ macOS dependencies ready"
REMOTE

  elif [[ "$platform" == "ubuntu" ]]; then
    # Ubuntu best practice:
    #   1. apt install tmux fzf ruby-full (system packages, stable)
    #   2. sudo gem install tmuxinator (into /usr/local/bin, needs sudo)
    #   3. zoxide via official install script (apt version is older)
    #   Prerequisite: the SSH user needs passwordless sudo; configure it first.
    if ! run_remote "$user" "$host" "sudo -n true" 2>/dev/null; then
      echo "⚠️  $host: user '$user' needs passwordless sudo. Configure NOPASSWD first:"
      echo "    ssh $user@$host"
      echo "    echo '$user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/99-$user-nopasswd"
      echo "    sudo chmod 440 /etc/sudoers.d/99-$user-nopasswd"
      echo "  Re-run sync.sh once configured."
      return 1
    fi
    run_remote "$user" "$host" 'bash' << 'REMOTE'
set -e
sudo apt-get update -qq
command -v tmux >/dev/null 2>&1 || sudo apt-get install -y tmux
command -v fzf  >/dev/null 2>&1 || sudo apt-get install -y fzf
dpkg -l ruby-full >/dev/null 2>&1 || sudo apt-get install -y ruby-full
command -v tmuxinator >/dev/null 2>&1 || sudo gem install tmuxinator --no-document
# zoxide: install to ~/.local/bin via curl (apt's 0.8 is too old)
if ! command -v zoxide >/dev/null 2>&1; then
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh || true
fi
echo "✓ Ubuntu dependencies ready"
REMOTE

  elif [[ "$platform" == "openwrt" ]]; then
    # OpenWrt: only install tmux + sftp-server (needed for scp file pushes)
    run_remote "$user" "$host" << 'REMOTE'
set -e
command -v tmux >/dev/null 2>&1 || opkg install tmux
opkg list-installed | grep -q openssh-sftp-server || opkg install openssh-sftp-server
echo "✓ OpenWrt dependencies ready"
REMOTE
  fi
}

# ── Push a single file (with diff confirmation) ─────────────────────────────
push_file() {
  local src="$1" user="$2" host="$3" dst="$4"
  local dst_dir
  dst_dir=$(dirname "$dst")

  run_remote "$user" "$host" "mkdir -p $dst_dir" 2>/dev/null || true

  local remote_content local_content
  remote_content=$(run_remote "$user" "$host" "cat $dst 2>/dev/null" || true)
  local_content=$(cat "$src")

  if [[ "$remote_content" == "$local_content" ]]; then
    echo "  $dst: no change"
    return 0
  fi

  if [[ -n "$remote_content" ]]; then
    echo ""
    echo "  ── diff: $dst ──"
    diff <(echo "$remote_content") <(echo "$local_content") \
      | head -50 | sed 's/^/    /' || true
    echo ""
  else
    echo "  $dst: new file (does not exist on remote)"
  fi

  $DRY_RUN && { echo "  [dry-run] skipping push: $dst"; return 0; }

  if ! $FORCE; then
    read -rp "  Push $dst? [y/N] " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { echo "  skipped $dst"; return 0; }
  fi

  scp_push "$src" "$user" "$host" "$dst"
  echo "  ✓ pushed: $dst"
}

# ── Push t.zsh (minimal variant for OpenWrt) ────────────────────────────────
push_tzsh() {
  local user="$1" host="$2" platform="$3"

  if [[ "$platform" == "openwrt" ]]; then
    # OpenWrt only gets a minimal t.zsh (no fzf/sesh dependency)
    local tmp_tzsh
    tmp_tzsh=$(mktemp "${TMPDIR:-/tmp}/t_openwrt_XXXXXX.zsh")
    cat > "$tmp_tzsh" << 'OPENWRT_TZSH'
# t.zsh — OpenWrt minimal variant (no fzf/sesh/tmuxinator)
# Provides only basic tmux session management

t() {
  local cmd="${1:-}"
  case "$cmd" in
    ls|list) tmux ls 2>/dev/null || echo "(no active sessions)" ;;
    new)
      local name="${2:-$(hostname)_main}"
      tmux new-session -d -s "$name" 2>/dev/null || true
      tmux attach -t "$name"
      ;;
    kill|stop) tmux kill-session -t "${2:?session name required}" ;;
    --version) echo "t 0.2.0 (OpenWrt minimal)" ;;
    "")
      # Attach to the first session, or create one
      local first
      first=$(tmux ls -F '#{session_name}' 2>/dev/null | head -1 || true)
      if [[ -n "$first" ]]; then
        tmux attach -t "$first"
      else
        local sname
        sname="$(hostname)_main"
        tmux new-session -s "$sname"
      fi
      ;;
    *) echo "t: unknown command '$cmd'"; echo "usage: t [ls|new <name>|kill <name>|--version]" ;;
  esac
}
OPENWRT_TZSH
    push_file "$tmp_tzsh" "$user" "$host" "~/.zsh/t.zsh"
    rm -f "$tmp_tzsh"
  else
    push_file "$TPL_DIR/t.zsh" "$user" "$host" "~/.zsh/t.zsh"
  fi
}

# ── Configure .zshrc / .profile source ──────────────────────────────────────
configure_shell() {
  local user="$1" host="$2" platform="$3"
  $DRY_RUN && { echo "  [dry-run] skipping shell configuration"; return 0; }

  if [[ "$platform" == "openwrt" ]]; then
    # OpenWrt uses /etc/profile (no ~/.zshrc)
    run_remote "$user" "$host" '
      grep -qF "source ~/.zsh/t.zsh" /etc/profile 2>/dev/null || \
      echo "[ -f ~/.zsh/t.zsh ] && source ~/.zsh/t.zsh" >> /etc/profile
    '
    echo "  ✓ /etc/profile source configured"

  elif [[ "$platform" == "macos" ]]; then
    # macOS best practice:
    #   - ~/.zshrc:    interactive shells (source t.zsh)
    #   - ~/.zprofile: login shells (brew shellenv + gem bin PATH)
    #   zsh rules: login shells read .zprofile, not .zshrc
    #              interactive shells read .zshrc, not .zprofile
    #              SSH login = login + interactive, so both are read
    # brew shellenv is resolved dynamically via `command -v brew` so this
    # works on both Apple Silicon (/opt/homebrew) and Intel (/usr/local).
    run_remote "$user" "$host" '
      # .zshrc: source t.zsh
      grep -qF "source ~/.zsh/t.zsh" ~/.zshrc 2>/dev/null || \
        echo "source ~/.zsh/t.zsh" >> ~/.zshrc

      # .zprofile: brew shellenv (login shell PATH base), brew path auto-detected
      if ! grep -qF "brew shellenv" ~/.zprofile 2>/dev/null; then
        _brew="$(command -v brew || { [ -x /opt/homebrew/bin/brew ] && echo /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && echo /usr/local/bin/brew; })"
        [ -n "$_brew" ] && echo "eval \"\$($_brew shellenv)\"" >> ~/.zprofile
      fi

      # .zprofile: BREW_GEM_PATH_INIT (gem bins such as tmuxinator)
      if ! grep -qF "BREW_GEM_PATH_INIT" ~/.zprofile 2>/dev/null; then
        cat >> ~/.zprofile << '"'"'BLOCK'"'"'

# BREW_GEM_PATH_INIT — brew ruby gem bins (tmuxinator etc.)
if command -v brew &>/dev/null; then
  _brew_ruby_bin="$(brew --prefix ruby 2>/dev/null)/bin"
  _brew_gem_bin="$( ${_brew_ruby_bin}/gem env gemdir 2>/dev/null )/bin"
  export PATH="${_brew_gem_bin}:${_brew_ruby_bin}:$PATH"
  unset _brew_ruby_bin _brew_gem_bin
fi
BLOCK
      fi
    '
    echo "  ✓ ~/.zshrc + ~/.zprofile configured (brew + gem PATH + t.zsh)"

  else
    # Ubuntu
    run_remote "$user" "$host" '
      grep -qF "source ~/.zsh/t.zsh" ~/.zshrc 2>/dev/null || \
      echo "source ~/.zsh/t.zsh" >> ~/.zshrc
    '
    echo "  ✓ ~/.zshrc source configured"
  fi
}

# ── Push tmux.conf ──────────────────────────────────────────────────────────
push_tmux_conf() {
  local user="$1" host="$2" platform="$3"

  if [[ "$platform" == "openwrt" ]]; then
    # OpenWrt gets a trimmed tmux.conf (drops macOS-only pbcopy etc.)
    local tmp_conf
    tmp_conf=$(mktemp "${TMPDIR:-/tmp}/tmux_openwrt_XXXXXX.conf")
    grep -v "pbcopy\|reattach-to-user\|set -g default-command" \
      "$TPL_DIR/tmux.conf" > "$tmp_conf" 2>/dev/null || cp "$TPL_DIR/tmux.conf" "$tmp_conf"
    push_file "$tmp_conf" "$user" "$host" "~/.tmux.conf"
    rm -f "$tmp_conf"
  else
    push_file "$TPL_DIR/tmux.conf" "$user" "$host" "~/.tmux.conf"
  fi
}

# ── Verify ──────────────────────────────────────────────────────────────────
verify_deploy() {
  local hid="$1" user="$2" host="$3" platform="$4"
  local pass=0 fail=0

  echo "→ Verifying..."

  _check() {
    local label="$1" cmd="$2"
    if run_remote "$user" "$host" "$cmd" >/dev/null 2>&1; then
      echo "  ✓ $label"; pass=$((pass+1))
    else
      echo "  ✗ $label"; fail=$((fail+1))
    fi
  }

  _check "tmux executable"     "tmux -V"
  _check "~/.tmux.conf exists"  "test -f ~/.tmux.conf"
  _check "~/.zsh/t.zsh exists"  "test -f ~/.zsh/t.zsh"

  if [[ "$platform" == "macos" || "$platform" == "ubuntu" ]]; then
    _check "fzf executable"        "fzf --version"
    _check "tmuxinator executable" "tmuxinator version"
    _check ".zshrc sources t.zsh"  "grep -q 't.zsh' ~/.zshrc"
  else
    _check "/etc/profile source" "grep -q 't.zsh' /etc/profile"
  fi

  echo ""
  if [[ $fail -eq 0 ]]; then
    echo "  [$hid] ✅ verification passed ($pass checks)"
    return 0
  else
    echo "  [$hid] ❌ verification failed ($fail failed, $pass passed)"
    return 1
  fi
}

# ── Test SSH and print confirmation message ─────────────────────────────────
test_and_announce() {
  local hid="$1" user="$2" host="$3"
  echo ""
  echo -n "→ SSH connectivity test... "
  local msg
  msg=$(run_remote "$user" "$host" \
    "echo \"[$(hostname)] tmux-setup ready — deployed successfully ($(date '+%Y-%m-%d %H:%M'))\"" 2>/dev/null || true)
  if [[ -n "$msg" ]]; then
    echo "✓"
    echo "  Remote output: $msg"
  else
    echo "✗ connectivity test failed"
  fi
}

# ── Local (this machine) sync ───────────────────────────────────────────────
sync_local() {
  local hid="$1"
  echo ""
  echo "══════════════════════════════════════════════════════"
  echo "  Target: $hid  (this machine, no SSH)"
  $DRY_RUN && echo "  Mode: DRY RUN"
  echo "══════════════════════════════════════════════════════"

  echo "  ── Current state ──"
  tmux -V 2>/dev/null && echo "  tmux: ✓ $(tmux -V)" || echo "  tmux: ✗"
  fzf --version 2>/dev/null | head -1 && true || echo "  fzf: ✗"
  tmuxinator version 2>/dev/null || echo "  tmuxinator: ✗ (check .zprofile in a new shell)"
  test -f ~/.zsh/t.zsh && echo "  t.zsh: ✓" || echo "  t.zsh: ✗"
  grep -q "t.zsh" ~/.zshrc 2>/dev/null && echo "  .zshrc source: ✓" || echo "  .zshrc source: ✗"
  grep -q "BREW_GEM_PATH_INIT" ~/.zprofile 2>/dev/null && echo "  .zprofile gem PATH: ✓" || echo "  .zprofile gem PATH: ✗"
  echo ""

  $DRY_RUN && { echo "  [dry-run] not modifying this machine"; return 0; }

  if ! $FORCE; then
    read -rp "  Continue syncing this machine ($hid)? [y/N] " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { echo "  skipped $hid"; return 0; }
  fi

  # Push tmux.conf
  if [[ ! -f ~/.tmux.conf ]] || ! diff -q "$TPL_DIR/tmux.conf" ~/.tmux.conf >/dev/null 2>&1; then
    cp "$TPL_DIR/tmux.conf" ~/.tmux.conf && echo "  ✓ ~/.tmux.conf updated"
  else
    echo "  ~/.tmux.conf: no change"
  fi

  # Push t.zsh
  mkdir -p ~/.zsh
  if [[ ! -f ~/.zsh/t.zsh ]] || ! diff -q "$TPL_DIR/t.zsh" ~/.zsh/t.zsh >/dev/null 2>&1; then
    cp "$TPL_DIR/t.zsh" ~/.zsh/t.zsh && echo "  ✓ ~/.zsh/t.zsh updated"
  else
    echo "  ~/.zsh/t.zsh: no change"
  fi

  # .zshrc source
  grep -qF "source ~/.zsh/t.zsh" ~/.zshrc 2>/dev/null || \
    { echo "source ~/.zsh/t.zsh" >> ~/.zshrc; echo "  ✓ .zshrc source configured"; }

  # .zprofile: brew shellenv (brew path auto-detected: Apple Silicon or Intel)
  if ! grep -qF "brew shellenv" ~/.zprofile 2>/dev/null; then
    _brew="$(command -v brew || { [ -x /opt/homebrew/bin/brew ] && echo /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && echo /usr/local/bin/brew; })"
    if [[ -n "$_brew" ]]; then
      echo "eval \"\$($_brew shellenv)\"" >> ~/.zprofile
      echo "  ✓ .zprofile brew shellenv configured"
    fi
    unset _brew
  fi

  # .zprofile: BREW_GEM_PATH_INIT
  if ! grep -qF "BREW_GEM_PATH_INIT" ~/.zprofile 2>/dev/null; then
    cat >> ~/.zprofile << 'BLOCK'

# BREW_GEM_PATH_INIT — brew ruby gem bins (tmuxinator etc.)
if command -v brew &>/dev/null; then
  _brew_ruby_bin="$(brew --prefix ruby 2>/dev/null)/bin"
  _brew_gem_bin="$( ${_brew_ruby_bin}/gem env gemdir 2>/dev/null )/bin"
  export PATH="${_brew_gem_bin}:${_brew_ruby_bin}:$PATH"
  unset _brew_ruby_bin _brew_gem_bin
fi
BLOCK
    echo "  ✓ .zprofile BREW_GEM_PATH_INIT configured"
  fi

  echo ""
  echo "  [$hid] ✅ local sync complete (open a new shell to apply)"
}

# ── Core: deploy a single machine ───────────────────────────────────────────
sync_one() {
  local host_id="$1"
  local dev_entry
  dev_entry=$(find_device "$host_id") || {
    echo "❌ unknown machine: $host_id"; return 1
  }

  local hid platform ssh_user ssh_host dname
  IFS='|' read -r hid platform ssh_user ssh_host dname <<< "$dev_entry"

  # Special case: this machine
  if [[ "$platform" == "local" ]]; then
    sync_local "$hid"
    return $?
  fi

  echo ""
  echo "══════════════════════════════════════════════════════"
  echo "  Target: $hid  ($dname)"
  echo "  SSH:    ${ssh_user}@${ssh_host}  [$platform]"
  $DRY_RUN && echo "  Mode: DRY RUN (diff only, no changes)"
  echo "══════════════════════════════════════════════════════"

  # Connectivity
  test_ssh "$ssh_user" "$ssh_host" "$hid" || return 1

  # Current state
  detect_status "$ssh_user" "$ssh_host" "$platform" "$hid"
  echo ""

  if $DRY_RUN; then
    echo "── Dry-run: files that would change ──"
    push_tmux_conf "$ssh_user" "$ssh_host" "$platform"
    push_tzsh      "$ssh_user" "$ssh_host" "$platform"
    return 0
  fi

  # Confirm before executing
  if ! $FORCE; then
    read -rp "  Continue syncing $hid? [y/N] " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { echo "  skipped $hid"; return 0; }
  fi

  # Install dependencies
  install_deps "$ssh_user" "$ssh_host" "$platform"

  # Push configuration
  echo "→ Pushing config files..."
  push_tmux_conf "$ssh_user" "$ssh_host" "$platform"
  push_tzsh      "$ssh_user" "$ssh_host" "$platform"
  configure_shell "$ssh_user" "$ssh_host" "$platform"

  # Verify
  verify_deploy "$hid" "$ssh_user" "$ssh_host" "$platform"

  # SSH connectivity confirmation
  test_and_announce "$hid" "$ssh_user" "$ssh_host"
}

# ── Show menu ────────────────────────────────────────────────────────────────
show_menu() {
  echo ""
  echo "tmux-setup sync"
  echo ""
  echo "Deployable machines:"
  echo ""
  local i=1
  for dev in "${DEVICES[@]}"; do
    IFS='|' read -r hid platform _u _h dname <<< "$dev"
    local plabel
    case "$platform" in
      macos)   plabel="macOS"   ;;
      ubuntu)  plabel="Ubuntu"  ;;
      openwrt) plabel="OpenWrt" ;;
      *)       plabel="$platform" ;;
    esac
    printf "  %d. %-20s [%-7s]  %s\n" "$i" "$hid" "$plabel" "$dname"
    i=$((i+1))
  done
  echo ""
  echo "  Enter numbers (comma-separated), all=every machine, q=quit"
  echo ""
}

parse_selection() {
  local input="$1"
  local -a selected=()
  if [[ "$input" == "all" ]]; then
    for dev in "${DEVICES[@]}"; do
      IFS='|' read -r hid _ _ _ _ <<< "$dev"
      selected+=("$hid")
    done
  else
    local -a nums
    IFS=',' read -ra nums <<< "$input"
    for n in "${nums[@]}"; do
      n="${n// /}"
      local idx=$(( n - 1 ))
      if [[ $idx -ge 0 && $idx -lt ${#DEVICES[@]} ]]; then
        IFS='|' read -r hid _ _ _ _ <<< "${DEVICES[$idx]}"
        selected+=("$hid")
      else
        echo "  invalid number: $n" >&2
      fi
    done
  fi
  printf '%s\n' "${selected[@]}"
}

# ── Main entry point ──────────────────────────────────────────────────────────
main() {
  # Load machine inventory before anything consumes DEVICES.
  load_devices

  local -a targets=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)  DRY_RUN=true;  shift ;;
      --force|-f) FORCE=true;    shift ;;
      --all)
        for dev in "${DEVICES[@]}"; do
          IFS='|' read -r hid _ _ _ _ <<< "$dev"
          targets+=("$hid")
        done
        shift ;;
      -*)
        echo "usage: sync.sh [--dry-run] [--force] [--all] [host_id ...]"
        exit 1 ;;
      *)
        targets+=("$1"); shift ;;
    esac
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    show_menu
    read -rp "Select machines: " selection
    [[ "$selection" == "q" ]] && exit 0
    mapfile -t targets < <(parse_selection "$selection")
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "No machines selected"; exit 0
  fi

  local total="${#targets[@]}" current=0
  for hid in "${targets[@]}"; do
    current=$((current+1))
    echo ""
    echo "[$current/$total] $hid"
    sync_one "$hid" || true

    if [[ $current -lt $total ]] && ! $FORCE; then
      read -rp "Continue to next machine? [y/N] " cont
      [[ "$cont" =~ ^[yY]$ ]] || { echo "Aborted"; break; }
    fi
  done

  echo ""
  echo "══════════════════════════════════════════════════════"
  echo "  Sync complete ($current/$total machines processed)"
  echo "══════════════════════════════════════════════════════"
}

main "$@"
