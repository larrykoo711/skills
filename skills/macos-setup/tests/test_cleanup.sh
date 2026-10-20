#!/usr/bin/env bash
# test_cleanup.sh — cleanup.sh must visit every blocklist item even when a removal command
# reads stdin (brew uninstall of some casks does): the list may not share stdin with the body.
set -u
cd "$(dirname "$0")/.." || exit 2
FAILS=0
t() { if eval "$2"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; FAILS=$((FAILS+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# a brew that lists two formulas and, like a cask's uninstall hook, swallows its stdin
cat > "$T/bin/brew" <<'EOF'
#!/bin/sh
case "$1" in
  list) printf 'aaa\nbbb\n' ;;
  uninstall) cat >/dev/null ;;
esac
EOF
chmod +x "$T/bin/brew"
printf 'formula\taaa\nformula\tbbb\n' > "$T/blocklist.txt"

# /dev/tty is where cleanup reads its y/N: give it a pty fed with "y"
# shellcheck disable=SC2034  # read inside the eval strings below
out="$(yes y | PATH="$T/bin:$PATH" MACOS_SETUP_BLOCKLIST="$T/blocklist.txt" MACOS_SETUP_LEDGER="$T/ledger.tsv" \
  perl -e 'alarm 30; exec @ARGV' script -q /dev/null bash scripts/cleanup.sh 2>&1 | tr -d '\r')"
t "first item removed" "printf '%s' \"\$out\" | grep -q 'removed formula aaa'"
t "item after a stdin-reading removal still visited" "printf '%s' \"\$out\" | grep -q 'removed formula bbb'"
t "ledger records both" "[ \"\$(grep -c . '$T/ledger.tsv' 2>/dev/null)\" = 2 ]"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
