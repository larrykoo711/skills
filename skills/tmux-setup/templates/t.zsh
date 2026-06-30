# t — tmux session tools
# version: 0.2.0
# author:  larrykoo711
# desc:    One nice tmux tool.
# deps:    tmux, fzf, tmuxinator, sesh, zoxide
# compat:  zsh on macOS + Ubuntu

# ── helper scripts (called by fzf execute-silent) ─────────────
# fzf execute[...] passes {} as $1; scripts avoid all quoting/bracket issues.
# Written to a per-user private directory (NOT a world-writable, predictable
# /tmp path) so other users on a shared host can't pre-create or hijack them.
_T_HELPER_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/t"
mkdir -p "$_T_HELPER_DIR" 2>/dev/null
chmod 700 "$_T_HELPER_DIR" 2>/dev/null

cat > "$_T_HELPER_DIR/_t_fzf_stop.sh" << 'HELPER'
#!/usr/bin/env zsh
# $1 is full fzf line: "▶ name" (running) or "○ name" (stopped template)
_n=$(echo "$1" | awk '{print ($1=="▶"||$1=="○") ? $2 : $1}')
_c=$(tmux display-message -p '#S' 2>/dev/null)
[[ -n "$_n" && "$_n" != "+" && "$_n" != "$_c" ]] && tmux kill-session -t "$_n" 2>/dev/null
HELPER
chmod +x "$_T_HELPER_DIR/_t_fzf_stop.sh"

cat > "$_T_HELPER_DIR/_t_fzf_remove.sh" << 'HELPER'
#!/usr/bin/env zsh
# $1 is full fzf line: "▶ name" (running) or "○ name" (stopped template)
_n=$(echo "$1" | awk '{print ($1=="▶"||$1=="○") ? $2 : $1}')
_c=$(tmux display-message -p '#S' 2>/dev/null)
if [[ -n "$_n" && "$_n" != "+" && "$_n" != "$_c" ]]; then
  tmux kill-session -t "$_n" 2>/dev/null
  rm -f "$HOME/.config/tmuxinator/${_n}.yml"
fi
HELPER
chmod +x "$_T_HELPER_DIR/_t_fzf_remove.sh"

cat > "$_T_HELPER_DIR/_t_fzf_list_sessions.sh" << 'HELPER'
#!/usr/bin/env zsh
source ~/.zsh/t.zsh
_t_session_list
HELPER
chmod +x "$_T_HELPER_DIR/_t_fzf_list_sessions.sh"

cat > "$_T_HELPER_DIR/_t_fzf_list_windows.sh" << 'HELPER'
#!/usr/bin/env zsh
source ~/.zsh/t.zsh
_t_window_list
HELPER
chmod +x "$_T_HELPER_DIR/_t_fzf_list_windows.sh"

cat > "$_T_HELPER_DIR/_t_fzf_list_folders.sh" << 'HELPER'
#!/usr/bin/env zsh
source ~/.zsh/t.zsh
_t_folder_list
HELPER
chmod +x "$_T_HELPER_DIR/_t_fzf_list_folders.sh"

# ── internal helpers ──────────────────────────────────────────

_t_sanitize_name() {
  echo "$1" | LC_ALL=C tr -cd 'a-zA-Z0-9._-' | tr ' ' '-' | tr 'A-Z' 'a-z'
}

_t_strip_prefix() {
  echo "$1" | awk '{print ($1=="▶"||$1=="○") ? $2 : $1}'
}

_t_host_prefix() {
  local raw
  if [[ "$(uname)" == "Darwin" ]]; then
    raw=$(scutil --get LocalHostName 2>/dev/null || hostname -s)
  else
    raw=$(hostname -s 2>/dev/null || echo "host")
  fi
  _t_sanitize_name "$raw"
}

_t_current_session() {
  tmux display-message -p '#S' 2>/dev/null
}

_t_session_list() {
  # collect into arrays — avoids pipe subshell scoping bug
  local running=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && running+=("$name")
  done < <(tmux ls 2>/dev/null | awk -F: '{print $1}')

  local templates=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && templates+=("$name")
  done < <(tmuxinator list -n 2>/dev/null | tail -n +2)

  # running sessions (prefix ▶ )
  for name in "${running[@]}"; do
    echo "▶ ${name}"
  done

  # stopped tmuxinator templates (prefix ○ )
  for name in "${templates[@]}"; do
    local found=false
    for r in "${running[@]}"; do [[ "$r" == "$name" ]] && found=true && break; done
    $found || echo "○ ${name}"
  done

  echo "  + new session"
}

_t_window_list() {
  local session="${1:-$(_t_current_session)}"
  [[ -z "$session" ]] && return 0
  tmux list-windows -t "$session" -F '#{window_index}:#{window_name}#{?window_active, *,}' 2>/dev/null
}

_t_folder_list() {
  sesh list -z 2>/dev/null
}

_t_attach() {
  local name="$1"
  # strip prefix (▶/○) — session name is $2 if prefixed, $1 otherwise
  name=$(_t_strip_prefix "$name")
  if tmux has-session -t "$name" 2>/dev/null; then
    if [[ -n "$TMUX" ]]; then
      tmux switch-client -t "$name"
    else
      tmux attach -t "$name"
    fi
  elif command -v tmuxinator &>/dev/null && tmuxinator list -n 2>/dev/null | grep -qx "$name"; then
    tmuxinator start "$name"
  else
    sesh connect -T "$name" 2>/dev/null || { echo "error: session '$name' not found" >&2; return 1; }
  fi
}

_t_new_session() {
  local name="$1" dir="$2"
  name=$(_t_sanitize_name "$name")
  [[ -z "$name" ]] && { echo "error: invalid session name" >&2; return 1; }
  mkdir -p "$HOME/.config/tmuxinator"
  local tpl="$HOME/.config/tmuxinator/${name}.yml"
  if [[ ! -f "$tpl" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      printf 'name: %s\nroot: %s\n\nwindows:\n  - shell:\n  - claude: claude --version\n' "$name" "$dir" > "$tpl"
    else
      printf 'name: %s\nroot: %s\n\nwindows:\n  - shell:\n' "$name" "$dir" > "$tpl"
    fi
    echo "created: $tpl"
  fi
  tmuxinator start "$name"
}

_t_clean_session() {
  local session
  session=$(_t_current_session)
  [[ -z "$session" ]] && { echo "error: not inside a tmux session" >&2; return 1; }
  local windows count=0
  windows=$(tmux list-windows -t "$session" -F '#{window_index}:#{window_name}')
  while IFS=: read -r idx wname; do
    if [[ "$wname" != "shell" && "$wname" != "claude" ]]; then
      tmux kill-window -t "${session}:${idx}"
      echo "closed: $wname"
      ((count++)) || true
    fi
  done <<< "$windows"
  [[ $count -eq 0 ]] && echo "nothing to clean" || echo "done: closed $count window(s)"
}

_t_stop() {
  local name="$1"
  if [[ -z "$name" ]]; then
    name=$(tmux ls 2>/dev/null | awk -F: '{print $1}' | fzf \
      --prompt="stop > " --height=~100% --min-height=10 --reverse --border \
      --header="Stop session — keeps template, can restart later")
    [[ -z "$name" ]] && return 0
  fi
  if ! tmux has-session -t "$name" 2>/dev/null; then
    echo "error: '$name' is not running" >&2; return 1
  fi
  local current
  current=$(_t_current_session)
  if [[ "$current" == "$name" ]]; then
    print -n "warning: '$name' is your current session, terminal will exit. Continue? [y/N] "
    read -r confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { echo "aborted"; return 0; }
  fi
  tmux kill-session -t "$name" && echo "stopped: $name" || { echo "error: failed to stop '$name'" >&2; return 1; }
}

_t_rm() {
  local name="$1"
  if [[ -z "$name" ]]; then
    name=$(_t_session_list | grep -v '+ new session' | while IFS= read -r line; do _t_strip_prefix "$line"; done | grep -v '^$' | fzf \
      --prompt="rm > " --height=~100% --min-height=10 --reverse --border \
      --header="Remove session + template (permanent)")
    [[ -z "$name" ]] && return 0
  fi
  local current warn=""
  current=$(_t_current_session)
  [[ "$current" == "$name" ]] && warn=" (warning: this is your current session)"
  print -n "remove '$name'${warn}? [y/N] "
  read -r confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { echo "aborted"; return 0; }
  tmux kill-session -t "$name" 2>/dev/null || true
  local tpl="$HOME/.config/tmuxinator/${name}.yml"
  [[ -f "$tpl" ]] && rm "$tpl" && echo "removed template: $name"
  echo "removed: $name"
}

# ── fzf picker ────────────────────────────────────────────────

_t_picker() {
  local in_tmux=false
  [[ -n "$TMUX" ]] && in_tmux=true

  # header tabs: active tab marked with *
  local header_sessions header_windows header_folders
  if [[ "$in_tmux" == true ]]; then
    header_sessions="[1] sessions *  │  [2] windows   │  [3] folders"
    header_windows="[1] sessions   │  [2] windows *  │  [3] folders"
    header_folders="[1] sessions   │  [2] windows   │  [3] folders *"
  else
    header_sessions="[1] sessions *  │  [3] folders"
    header_windows="[1] sessions *  │  [3] folders"
    header_folders="[1] sessions   │  [3] folders *"
  fi

  local footer_sessions footer_windows footer_folders
  if [[ "$in_tmux" == true ]]; then
    footer_sessions="[d] detach  [s] stop  [x] remove  [r] refresh  [shift-←/→] tab"
  else
    footer_sessions="[s] stop  [x] remove  [r] refresh  [shift-←/→] tab"
  fi
  footer_windows="[r] refresh"
  footer_folders="[r] refresh"

  # use [...] not (...) — parens inside fzf actions cause parse failures (fzf docs)
  local reload_sessions="reload[$_T_HELPER_DIR/_t_fzf_list_sessions.sh]"
  local reload_windows="reload[$_T_HELPER_DIR/_t_fzf_list_windows.sh]"
  local reload_folders="reload[$_T_HELPER_DIR/_t_fzf_list_folders.sh]"

  # s: stop session (keep template), x: remove session + template
  local bind_s="s:execute-silent[$_T_HELPER_DIR/_t_fzf_stop.sh {}]+$reload_sessions"
  local bind_x="x:execute-silent[$_T_HELPER_DIR/_t_fzf_remove.sh {}]+$reload_sessions"

  # bind 2 + arrow keys — windows tab only inside tmux
  local bind_2 bind_left bind_right
  if [[ "$in_tmux" == true ]]; then
    bind_2="2:change-prompt(windows > )+change-header($header_windows)+change-footer($footer_windows)+$reload_windows"
    # sessions←→windows←→folders (circular via left/right)
    bind_left="shift-left:change-prompt(sessions > )+change-header($header_sessions)+change-footer($footer_sessions)+$reload_sessions"
    bind_right="shift-right:change-prompt(windows > )+change-header($header_windows)+change-footer($footer_windows)+$reload_windows"
  else
    bind_2="2:ignore"
    bind_left="shift-left:change-prompt(sessions > )+change-header($header_sessions)+change-footer($footer_sessions)+$reload_sessions"
    bind_right="shift-right:change-prompt(folders > )+change-header($header_folders)+change-footer($footer_folders)+$reload_folders"
  fi

  local tmpsel
  tmpsel=$(mktemp)

  _t_session_list | fzf \
    --prompt="sessions > " \
    --height=~100% \
    --min-height=10 \
    --reverse \
    --border \
    --ansi \
    --no-select-1 \
    --header="$header_sessions" \
    --footer="$footer_sessions" \
    --no-preview \
    --bind "1:change-prompt(sessions > )+change-header($header_sessions)+change-footer($footer_sessions)+$reload_sessions" \
    --bind "$bind_2" \
    --bind "3:change-prompt(folders > )+change-header($header_folders)+change-footer($footer_folders)+$reload_folders" \
    --bind "$bind_left" \
    --bind "$bind_right" \
    --bind "d:execute-silent(tmux detach-client 2>/dev/null)+abort" \
    --bind "$bind_s" \
    --bind "$bind_x" \
    --bind "r:$reload_sessions" \
    > "$tmpsel"

  local selection
  selection=$(cat "$tmpsel")
  rm -f "$tmpsel"

  [[ -z "$selection" ]] && return 0

  local name
  name=$(_t_strip_prefix "$selection")

  if [[ "$name" == "+" || "$selection" == *"+ new session"* ]]; then
    local prefix default_name
    prefix=$(_t_host_prefix)
    default_name="${prefix}_$(_t_sanitize_name "$(basename "$(pwd)")")"
    if tmux has-session -t "$default_name" 2>/dev/null || \
       tmuxinator list -n 2>/dev/null | grep -qx "$default_name"; then
      printf "'%s' already exists, enter new name: " "$default_name"
      read -r name
      [[ -z "$name" ]] && { echo "aborted"; return 0; }
      name=$(_t_sanitize_name "$name")
      [[ -z "$name" ]] && { echo "error: invalid name" >&2; return 1; }
      [[ "$name" != ${prefix}_* ]] && name="${prefix}_${name}"
    else
      name="$default_name"
    fi
    _t_new_session "$name" "$(pwd)"
  elif [[ "$name" =~ ^[0-9]+:.* ]]; then
    # window selection (format: index:name)
    local idx="${name%%:*}"
    local session
    session=$(_t_current_session)
    tmux select-window -t "${session}:${idx}"
  elif [[ -d "$name" || "$name" =~ ^/ || "$name" =~ ^~ ]]; then
    # folder from zoxide — create/connect session
    local sname
    sname="$(_t_host_prefix)_$(_t_sanitize_name "$(basename "$name")")"
    sesh connect -T "$sname" 2>/dev/null || _t_new_session "$sname" "$name"
  else
    _t_attach "$name"
  fi
}

# ── main ──────────────────────────────────────────────────────

t() {
  local cmd="${1:-}"

  case "$cmd" in

    --version|-v)
      local _f=~/.zsh/t.zsh
      local _ver _author _desc
      _ver=$(grep -m1    '^# version:' "$_f" | sed 's/^# version:[[:space:]]*//')
      _author=$(grep -m1 '^# author:'  "$_f" | sed 's/^# author:[[:space:]]*//')
      _desc=$(grep -m1   '^# desc:'    "$_f" | sed 's/^# desc:[[:space:]]*//')
      printf '\n'
      printf '   d8P\n'
      printf 'd888888P\n'
      printf "  ?88'\n"
      printf '  88P     %s\n'  "v${_ver} · ${_author}"
      printf '  88b     %s\n'  "${_desc}"
      printf '  `?8b\n'
      printf '\n'
      ;;

    -h|--help|help)
      cat << 'EOF'
t — tmux session tools

  USAGE
    t                   open interactive picker (main entry)
    t stop [name]       stop session, keep template (restartable)
    t rm   [name]       remove session + template permanently
    t clean             close temp windows in current session
    t update            reload zshrc + t.zsh in current shell
    t --version         show version
    t --help            show this help

  PICKER KEYS
    enter               attach / switch to session or window
    1                   switch to sessions view
    2                   switch to windows view (tmux only)
    3                   switch to folders view (zoxide)
    d                   detach current tmux client
    s                   stop selected session
    x                   remove selected session + template
    r              refresh list

  TMUX KEYS  (prefix = Ctrl-b)
    prefix + c          new window
    prefix + 1/2/3      switch window by number
    prefix + ,          rename current window
    prefix + w          native window/session list
    prefix + d          detach (session stays alive)
    prefix + &          close current window

  CONVENTIONS
    session name        <hostname>_<project>  e.g. koombp_my-computer
    fixed windows       1:shell  2:claude  (do not rename or delete)
    temp windows        3+  free naming, use 't clean' to purge
EOF
      ;;

    clean)
      _t_clean_session
      ;;

    stop)
      _t_stop "${2:-}"
      ;;

    rm)
      _t_rm "${2:-}"
      ;;

    update)
      source ~/.zshrc && echo "reloaded: zshrc + t.zsh"
      ;;

    "")
      _t_picker
      ;;

    *)
      echo "error: unknown command '$cmd'" >&2
      echo "run 't --help' for usage" >&2
      return 1
      ;;

  esac
}
