#!/usr/bin/env bash
# sync-user-env.sh — copy the human-curated user environment from THIS Mac (the source)
# to another Mac over SSH. Runs on the orchestrator, not on the target.
#
# The standard (Brewfile, defaults, agent-ready) makes machines equal; this script makes a
# new machine feel like the owner's: their Claude Code setup, their shell, their CC Switch
# providers. Everything here was once done by hand (pitfalls #44) — this is that, repeatable.
#
# Usage: sync-user-env.sh <ssh-target> [--only claude,claude-md,zshrc,cc-switch] [--dry-run]
#
# Kept per machine on purpose (never copied):
#   ~/.claude/settings.json "hooks"   — they point at binaries installed on each machine
#   ANTHROPIC_* in settings env       — the API provider is a per-machine choice
# Opt-outs (env, space-separated):
#   SYNC_SKIP_COMMANDS="a b"   ~/.claude/commands/<name>.md that stay on this Mac only
#   SYNC_SKIP_MCP="x y"        user MCP servers that each machine configures itself
#   SYNC_ZSHRC_MANAGED_TAG=t   ~/.zshrc blocks fenced "# >>> t…>>>" … "# <<< t…<<<" are written
#                              per machine by some tool: never copied, the target's own kept
# Secrets (MCP env, CC Switch keys) travel over SSH stdin only — never argv, never printed.
set -u
SKIP_COMMANDS="${SYNC_SKIP_COMMANDS:-}" SKIP_MCP="${SYNC_SKIP_MCP:-}" ZTAG="${SYNC_ZSHRC_MANAGED_TAG:-}"
export SKIP_MCP ZTAG
TARGET="${1:?usage: sync-user-env.sh <ssh-target> [--only list] [--dry-run]}"; shift
ONLY="claude,claude-md,zshrc,cc-switch" DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
want() { case ",$ONLY," in *",$1,"*) return 0 ;; esac; return 1; }
say() { printf '%s\n' "$*"; }
RPATH='export PATH=$HOME/.local/bin:$HOME/.local/share/fnm/aliases/default/bin:/opt/homebrew/bin:$PATH'
ssh -o ConnectTimeout=8 "$TARGET" true || { echo "cannot reach $TARGET" >&2; exit 2; }
[ "$DRY" = 1 ] && say "(dry run — nothing will be written on $TARGET)"

# ── claude: settings (minus hooks), agents, output-styles, commands, ccline, plugins, user MCP ──
if want claude; then
  say "── claude"
  python3 - > /tmp/sue-settings.json <<'EOF'
import json, os
d = json.load(open(os.path.expanduser('~/.claude/settings.json')))
d.pop('hooks', None)
# an API provider in env (CC Switch) is a per-machine choice, not part of the owner's setup
for k in [k for k in d.get('env', {}) if k.startswith('ANTHROPIC_')]: d['env'].pop(k)
print(json.dumps(d))
EOF
  if [ "$DRY" = 1 ]; then
    say "  settings keys: $(python3 -c 'import json; print(sorted(json.load(open("/tmp/sue-settings.json"))))')"
    say "  would rsync: agents output-styles ccline commands${SKIP_COMMANDS:+ (minus: $SKIP_COMMANDS)}"
  else
    # shellcheck disable=SC2029
    ssh "$TARGET" 'mkdir -p ~/.claude && python3 -c "
import json,os,sys
p=os.path.expanduser(\"~/.claude/settings.json\")
cur=json.load(open(p)) if os.path.exists(p) else {}
new=json.load(sys.stdin)
new[\"hooks\"]=cur.get(\"hooks\",{})                     # target keeps its own hooks
env=new.setdefault(\"env\",{})
env.update({k:v for k,v in cur.get(\"env\",{}).items() if k.startswith(\"ANTHROPIC_\")})  # and its provider
t=p+\".tmp\"; json.dump(new,open(t,\"w\"),indent=2,ensure_ascii=False); os.chmod(t,0o600); os.replace(t,p)
print(\"  settings.json:\", len(new), \"keys\")"' < /tmp/sue-settings.json
    excl=(); for c in $SKIP_COMMANDS; do excl+=(--exclude "$c.md"); done
    dirs=(); for d in agents output-styles ccline commands; do [ -d ~/.claude/$d ] && dirs+=("$d"); done
    if [ ${#dirs[@]} -gt 0 ]; then
      (cd ~/.claude && rsync -a ${excl[@]+"${excl[@]}"} "${dirs[@]}" "$TARGET:.claude/") && say "  ${dirs[*]} synced"
    fi
    plugins="$(python3 -c 'import json,os; print(" ".join(k for k,v in json.load(open(os.path.expanduser("~/.claude/settings.json"))).get("enabledPlugins",{}).items() if v))')"
    # shellcheck disable=SC2029
    ssh "$TARGET" "$RPATH; claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1; for p in $plugins; do claude plugin list 2>/dev/null | grep -q \"\$p\" || claude plugin install \"\$p\" >/dev/null 2>&1 && echo \"  plugin \$p ok\" || echo \"  plugin \$p FAILED\"; done"
    python3 - <<'EOF' | ssh "$TARGET" "$RPATH; umask 077; cat > /tmp/sue-mcp.json; python3 -c 'import json; [print(k) for k in json.load(open(\"/tmp/sue-mcp.json\"))]' | while read -r n; do claude mcp get \"\$n\" >/dev/null 2>&1 && { echo \"  mcp \$n present\"; continue; }; python3 -c 'import json,sys; print(json.dumps(json.load(open(\"/tmp/sue-mcp.json\"))[sys.argv[1]]))' \"\$n\" > /tmp/sue-mcp-one.json; claude mcp add-json -s user \"\$n\" \"\$(cat /tmp/sue-mcp-one.json)\" >/dev/null && echo \"  mcp \$n added\"; done; rm -f /tmp/sue-mcp*.json"
import json, os
d = json.load(open(os.path.expanduser('~/.claude.json'))).get('mcpServers', {})
for n in os.environ.get('SKIP_MCP', '').split(): d.pop(n, None)   # configured per machine
print(json.dumps(d))
EOF
  fi
  rm -f /tmp/sue-settings.json
fi

# ── claude-md: the owner's global instructions ──
if want claude-md; then
  say "── claude-md"
  if [ "$DRY" = 1 ]; then say "  would copy ~/.claude/CLAUDE.md ($(md5 -q ~/.claude/CLAUDE.md))"
  else scp -q ~/.claude/CLAUDE.md "$TARGET:.claude/CLAUDE.md.new" && ssh "$TARGET" 'mv -f ~/.claude/CLAUDE.md.new ~/.claude/CLAUDE.md && echo "  CLAUDE.md $(md5 -q ~/.claude/CLAUDE.md)"'; fi
fi

# ── zshrc: owner's personal part + the target's own managed blocks ──
if want zshrc; then
  say "── zshrc"
  python3 - > /tmp/sue-zshrc <<'EOF'
import os, re
s = open(os.path.expanduser('~/.zshrc')).read()
tag = re.escape(os.environ.get('ZTAG', ''))
if tag:   # managed per machine
    s = re.sub(r'# >>> ' + tag + r'[^\n]*>>>\n.*?# <<< ' + tag + r'[^\n]*<<<\n?', '', s, flags=re.S)
print(re.sub(r'\n{3,}', '\n\n', s).rstrip() + '\n')
EOF
  if [ "$DRY" = 1 ]; then
    say "  personal part: $(grep -c . /tmp/sue-zshrc) lines; would install oh-my-zsh if missing"
  else
    scp -q /tmp/sue-zshrc "$TARGET:/tmp/sue-zshrc"
    # shellcheck disable=SC2016,SC2029  # ZTAG expands here, the rest on the target
    ssh "$TARGET" "export ZTAG=$(printf '%q' "$ZTAG"); "'[ -d ~/.oh-my-zsh ] || git clone --quiet --depth 1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
      [ -f ~/.zshrc ] && cp ~/.zshrc ~/.zshrc.bak-$(date +%Y%m%d%H%M)
      python3 - <<PY
import os,re
p=os.path.expanduser("~/.zshrc"); mine=open(p).read() if os.path.exists(p) else ""
tag=re.escape(os.environ.get("ZTAG",""))
blocks="".join(re.findall(r"# >>> "+tag+r"[^\n]*>>>\n.*?# <<< "+tag+r"[^\n]*<<<\n", mine, flags=re.S)) if tag else ""
new=open("/tmp/sue-zshrc").read().rstrip()+"\n\n"+blocks
open(p+".tmp","w").write(new); os.replace(p+".tmp",p)
print("  .zshrc: personal part +", len(re.findall(r"# >>> "+tag, blocks)) if tag else 0, "managed blocks kept")
PY
      rm -f /tmp/sue-zshrc
      err="$(zsh -i -c exit 2>&1 >/dev/null)"; [ -z "$err" ] && echo "  interactive zsh starts clean" || { echo "  zsh startup stderr:"; echo "$err" | head -5; }'
  fi
  rm -f /tmp/sue-zshrc
fi

# ── cc-switch: providers and settings, without this Mac's request history ──
if want cc-switch; then
  say "── cc-switch"
  if [ ! -f ~/.cc-switch/cc-switch.db ]; then say "  no CC Switch config on this Mac — skipped"
  elif [ "$DRY" = 1 ]; then say "  would snapshot ~/.cc-switch/cc-switch.db (history cleared) → $TARGET:~/.cc-switch (600)"
  else
    T="$(mktemp -d)"
    sqlite3 ~/.cc-switch/cc-switch.db ".backup '$T/cc-switch.db'" \
      && sqlite3 "$T/cc-switch.db" "DELETE FROM proxy_request_logs; DELETE FROM stream_check_logs; DELETE FROM session_usage_dedup; DELETE FROM usage_daily_rollups; DELETE FROM session_log_sync; DELETE FROM provider_health; VACUUM;"
    # the target's current provider is its own choice — keep it if it already has a config
    # The app must be fully gone (it flushes on quit) before its files are replaced.
    ssh "$TARGET" 'osascript -e "tell application \"CC Switch\" to quit" 2>/dev/null; for _ in $(seq 1 20); do pgrep -f "CC Switch.app" >/dev/null || break; sleep 1; done; pgrep -f "CC Switch.app" >/dev/null && { echo "  CC Switch did not quit — skipped" >&2; exit 1; }; install -d -m 700 ~/.cc-switch; [ -f ~/.cc-switch/cc-switch.db ] && cp ~/.cc-switch/cc-switch.db ~/.cc-switch/cc-switch.db.bak-$(date +%Y%m%d%H%M); true' || { rm -rf "$T"; exit 1; }
    scp -q "$T/cc-switch.db" "$TARGET:.cc-switch/cc-switch.db.new" && rm -rf "$T"
    # shellcheck disable=SC2016
    ssh "$TARGET" 'cd ~/.cc-switch && if [ -f cc-switch.db ]; then
        # one row per app type; while-read (not for-in): the login shell may be zsh, which does not word-split
        sqlite3 -separator "|" cc-switch.db "SELECT app_type, id FROM providers WHERE is_current=1" | while IFS="|" read -r a i; do
          sqlite3 cc-switch.db.new "UPDATE providers SET is_current=CASE WHEN id=\"$i\" THEN 1 ELSE 0 END WHERE app_type=\"$a\""; done
      fi
      # a leftover WAL/SHM would replay the OLD database into the new one on next open
      rm -f cc-switch.db-wal cc-switch.db-shm
      chmod 600 cc-switch.db.new && mv -f cc-switch.db.new cc-switch.db && echo "  cc-switch.db installed (current providers kept: $(sqlite3 cc-switch.db "SELECT group_concat(app_type||\"=\"||name, \", \") FROM providers WHERE is_current=1"))"; open -a "CC Switch" 2>/dev/null; true'
  fi
fi
say "done — re-run with --dry-run any time to see what would change"
