#!/usr/bin/env bash
# test_with_cc_moss.sh — pipeline step 5b: cc-moss is opt-in, honours the exclude file, and
# passes MACOS_SETUP_CCMOSS_SKIP through as --skip flags. Runs the step alone against stubs.
set -u
cd "$(dirname "$0")/.." || exit 2
FAILS=0
t() { if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; FAILS=$((FAILS+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# brew "installs" cc-moss by putting a stub on PATH that records how it was called
cat > "$T/bin/brew" <<STUB
#!/bin/sh
echo "brew \$*" >> "$T/calls"
printf '#!/bin/sh\necho "cc-moss \$*" >> "$T/calls"\n' > "$T/bin/cc-moss"; chmod +x "$T/bin/cc-moss"
STUB
chmod +x "$T/bin/brew"
STEP="$(sed -n '/^# ── 5b\. cc-moss/,/^# ── 6\./p' scripts/pipeline.sh)"
[ -n "$STEP" ] || { echo "FAIL step 5b not found in pipeline.sh"; exit 1; }

# run step 5b with WITH=$1 and an exclude file holding $2
run() {
  rm -f "$T/calls" "$T/bin/cc-moss"; printf '%s\n' "$2" > "$T/exclude"
  PATH="$T/bin:/usr/bin:/bin" WITH="$1" EXCLUDE="$T/exclude" STEP="$STEP" bash -c '
    have() { command -v "$1" >/dev/null 2>&1; }
    msg() { :; }; report_ok() { :; }; report_finding() { echo "finding: $*" >> "'"$T"'/calls"; }
    excluded() { grep -qxF "$1" "$EXCLUDE"; }
    with() { case ",$WITH," in *",$1,"*) return 0 ;; esac; return 1; }
    eval "$STEP"'
}

run "" ""
t "not asked for: nothing installed" "[ ! -s '$T/calls' ]"
run ",cc-moss" ""
t "--with cc-moss installs from the tap" "grep -qx 'brew install larrykoo711/tap/cc-moss' '$T/calls'"
t "then sets it up without asking" "grep -qx 'cc-moss install --yes' '$T/calls'"
run ",cc-moss" "cc-moss"
t "an exclude line skips it" "[ ! -s '$T/calls' ]"
MACOS_SETUP_CCMOSS_SKIP="tmux starship" run ",cc-moss" ""
t "MACOS_SETUP_CCMOSS_SKIP becomes --skip flags" "grep -qx 'cc-moss install --yes --skip tmux --skip starship' '$T/calls'"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
