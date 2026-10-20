#!/usr/bin/env bash
# test_agent_ready.sh — structural guards for the agent-ready standard.
# The tsv is the single source of truth: every id must have a check function,
# every auto id an apply function, and the engine must never count unknown as pass.
set -u
cd "$(dirname "$0")/.." || exit 2
TSV=standard/agent-ready.tsv ENGINE=scripts/agent-ready.sh
FAILS=0
t() { if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; FAILS=$((FAILS+1)); fi; }

ids()      { grep -vE '^\s*(#|$)' "$TSV" | cut -f1; }
auto_ids() { grep -vE '^\s*(#|$)' "$TSV" | awk -F'\t' '$3=="auto"{print $1}'; }
fn()       { printf 'ar_%s' "$(printf '%s' "$1" | tr '-' '_')"; }

t "tsv exists" "[ -f $TSV ]"
t "engine passes bash -n" "bash -n $ENGINE"
t "tsv rows have 5 fields" "! grep -vE '^\s*(#|\$)' $TSV | awk -F'\t' 'NF!=5{bad=1} END{exit !bad}'"
t "mode is auto|manual|check" "! grep -vE '^\s*(#|\$)' $TSV | awk -F'\t' '\$3!~/^(auto|manual|check)\$/{bad=1} END{exit !bad}'"
t "ids are unique" "[ -z \"\$(ids | sort | uniq -d)\" ]"

missing_check="" missing_apply=""
for id in $(ids); do grep -q "^$(fn "$id")_check()" "$ENGINE" || missing_check="$missing_check $id"; done
for id in $(auto_ids); do grep -q "^$(fn "$id")_apply()" "$ENGINE" || missing_apply="$missing_apply $id"; done
t "every id has a check function${missing_check:+ (missing:$missing_check)}" "[ -z '$missing_check' ]"
t "every auto id has an apply function${missing_apply:+ (missing:$missing_apply)}" "[ -z '$missing_apply' ]"
# unknown must never be tallied as pass
t "unknown is not counted as pass" "! grep -nE 'unknown\).*PASS' $ENGINE"
t "list mode runs without root" "bash $ENGINE --list >/dev/null"

# the layer is opt-in: pipeline/verify reach agent-ready only behind the agent-node profile
t "pipeline gates agent-ready on the profile" "grep -B2 'agent-ready.sh' scripts/pipeline.sh | grep -q 'PROFILE\" = agent-node ]'"
t "verify gates agent-ready on the profile" "grep 'agent-ready.sh' scripts/verify.sh | grep -q 'current_profile)\" = agent-node ]'"
t "bootstrap and engine map dotted user names the same way" "grep -q 'macos-setup-\$(printf .%s. \"\$TUSER\" | tr . _)' scripts/agent-bootstrap.sh && grep -q 'macos-setup-\$(printf .%s. \"\$USER\" | tr . _)' scripts/agent-ready.sh"
t "no bare \"\${jump[@]}\" (bash 3.2 + set -u dies on an empty array)" "! grep -n '\"\${jump\[@\]}\"' scripts/agent-bootstrap.sh | grep -v '+\"'"
KEYDIR="$(mktemp -d)"; trap 'rm -rf "$KEYDIR"' EXIT
ssh-keygen -q -t ed25519 -N '' -C test -f "$KEYDIR/k" >/dev/null
t "printed day-0 block is valid sh and uses mktemp" "bash scripts/agent-bootstrap.sh --pubkey '$KEYDIR/k.pub' | tail -n +3 | grep -q 'mktemp' && bash scripts/agent-bootstrap.sh --pubkey '$KEYDIR/k.pub' | tail -n +3 | bash -n"
# every flag variable the pipeline tests must be initialised (set -u kills the run otherwise)
for v in PROFILE PREREQS_ONLY SKIP_DEFAULTS SKIP_BUNDLE; do
  t "pipeline initialises $v" "grep -qE '^EXCLUDE=.* $v=' scripts/pipeline.sh"
done
t "remote steps run under caffeinate" "grep -q 'caffeinate -i bash scripts/' scripts/remote.sh"
t "pipeline holds off idle sleep" "grep -q 'caffeinate -i -w' scripts/pipeline.sh"
t "tailscale/docker probes are bounded" "grep -q 'bounded 10 \"\$ts\"' scripts/agent-ready.sh && grep -q 'bounded 15 docker' scripts/agent-ready.sh"
t "bounded ends a hanging command" "s=\$(date +%s); perl -e 'alarm shift; exec @ARGV' 1 sleep 5; [ \$? -eq 142 ] && [ \$((\$(date +%s)-s)) -lt 3 ]"
# behaviour: each item yields exactly one verdict line (a manual item once, never also as fail)
# empty HOME forces git-identity down the manual path, where the bug lived
# shellcheck disable=SC2034  # read inside the eval strings below
out="$(HOME="$(mktemp -d)" XDG_CONFIG_HOME=/nonexistent FINDINGS_FILE=/tmp/ar-test-findings.txt bash $ENGINE --check --only git-identity 2>/dev/null)"
t "one verdict per item" "[ \$(printf '%s\n' \"\$out\" | grep -c 'git-identity:') -eq 1 ]"
t "unknown --only id exits 2" "FINDINGS_FILE=/tmp/ar-t.txt bash $ENGINE --check --only no-such-item >/dev/null 2>&1; [ \$? -eq 2 ]"
t "standard is read on fd 3 (probes cannot swallow it)" "grep -q 'done 3< <(grep' $ENGINE"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
