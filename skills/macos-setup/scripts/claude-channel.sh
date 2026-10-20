#!/usr/bin/env bash
# claude-channel.sh — switch another Mac's Claude Code channel to one of its CC Switch
# providers, remotely and without the GUI. Runs on the orchestrator.
#
#   claude-channel.sh <ssh-target> --list
#   claude-channel.sh <ssh-target> <provider name>      e.g. "My Relay" · "Claude Official"
#
# What the CC Switch app would do, done so it sticks:
#   1. quit CC Switch (it rewrites settings.json and the DB from memory when it exits)
#   2. ~/.claude/settings.json: drop every ANTHROPIC_* / CLAUDE_CODE_MAX_CONTEXT_TOKENS key, merge
#      the provider's env in (backup first); the provider's other settings_config keys are NOT
#      applied — CC Switch's common config carries another machine's hooks
#   3. providers.is_current → this provider, then reopen the app
# Only NEW claude sessions pick it up: restart running ones (pitfalls #47).
# An API-token channel turns the claude.ai connectors off; "Claude Official" turns them back on.
# Secrets never leave the target: the merge runs there and prints key names only.
set -eu
TARGET="${1:?usage: claude-channel.sh <ssh-target> <provider name>|--list}"
NAME="${2:?usage: claude-channel.sh <ssh-target> <provider name>|--list}"

if [ "$NAME" = "--list" ]; then
  # shellcheck disable=SC2016
  ssh "$TARGET" 'sqlite3 -separator "  " ~/.cc-switch/cc-switch.db "SELECT CASE is_current WHEN 1 THEN \"*\" ELSE \" \" END, name FROM providers WHERE app_type=\"claude\" ORDER BY sort_index"'
  exit 0
fi
case "$NAME" in *"'"*) echo "provider name contains a single quote — refusing" >&2; exit 2 ;; esac

# shellcheck disable=SC2016
ssh "$TARGET" 'osascript -e "tell application \"CC Switch\" to quit" 2>/dev/null
  for _ in $(seq 1 20); do pgrep -f "CC Switch.app" >/dev/null || break; sleep 1; done
  pgrep -f "CC Switch.app" >/dev/null && { echo "CC Switch did not quit — nothing changed" >&2; exit 1; }
  true'

rc=0
# shellcheck disable=SC2029  # $NAME is meant to expand here; quotes were vetted above
ssh "$TARGET" "python3 - '$NAME'" <<'PY' || rc=$?
import json, os, shutil, sqlite3, sys, time
name = sys.argv[1]
db = os.path.expanduser("~/.cc-switch/cc-switch.db")
con = sqlite3.connect(db)
rows = con.execute("SELECT id, settings_config FROM providers WHERE app_type='claude' AND name=?", (name,)).fetchall()
if len(rows) != 1:
    sys.exit(f"provider {name!r}: {len(rows)} matches in CC Switch (use --list)")
pid, cfg = rows[0]
env = (json.loads(cfg or "{}").get("env") or {})

path = os.path.expanduser("~/.claude/settings.json")
settings = json.load(open(path)) if os.path.exists(path) else {}
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d%H%M%S')}")
cur = {k: v for k, v in (settings.get("env") or {}).items()
       if not (k.startswith("ANTHROPIC_") or k == "CLAUDE_CODE_MAX_CONTEXT_TOKENS")}
cur.update(env)
settings["env"] = cur
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
os.replace(tmp, path)

con.execute("UPDATE providers SET is_current = CASE WHEN id=? THEN 1 ELSE 0 END WHERE app_type='claude'", (pid,))
con.commit()

# read back: positive evidence, not "no error"
back = json.load(open(path)).get("env", {})
cur_db = con.execute("SELECT name FROM providers WHERE app_type='claude' AND is_current=1").fetchall()
ok = all(back.get(k) == v for k, v in env.items()) and cur_db == [(name,)]
print(f"  settings.json env ← {sorted(env) or '(none: official sign-in)'}")
print(f"  base url: {back.get('ANTHROPIC_BASE_URL', '(default)')} · model: {back.get('ANTHROPIC_MODEL', '(default)')}")
print(f"  CC Switch current: {cur_db[0][0] if cur_db else '?'}")
sys.exit(0 if ok else 1)
PY
ssh "$TARGET" 'open -a "CC Switch" 2>/dev/null; true'
[ $rc -eq 0 ] && echo "✓ $TARGET → $NAME (new sessions only; restart the running ones)"
exit $rc
