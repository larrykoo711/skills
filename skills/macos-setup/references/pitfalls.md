# macos-setup — field-tested pitfalls

Every entry below was hit in real setup runs. The scripts already encode the
countermeasures; this file explains *why* they look the way they do.

<details>
<summary><strong>Contents</strong> — 53 pitfalls (click to expand)</summary>

- [1. `defaults write` fails SILENTLY on modern macOS (the #1 trap)](#1-defaults-write-fails-silently-on-modern-macos-the-1-trap)
- [2. `brew bundle` fails on manually installed apps](#2-brew-bundle-fails-on-manually-installed-apps)
- [3. Casks that rename their app on install cannot adopt](#3-casks-that-rename-their-app-on-install-cannot-adopt)
- [4. Never uninstall the network transport you are riding](#4-never-uninstall-the-network-transport-you-are-riding)
- [5. mas has two hard human breakpoints](#5-mas-has-two-hard-human-breakpoints)
- [6. symbolichotkeys: never edit the plist, never read it by eye](#6-symbolichotkeys-never-edit-the-plist-never-read-it-by-eye)
- [7. `HOMEBREW_BUNDLE_NO_UPGRADE=1` is mandatory](#7-homebrew_bundle_no_upgrade1-is-mandatory)
- [8. Cleanup is a high-risk, standalone action](#8-cleanup-is-a-high-risk-standalone-action)
- [9. Plan first — zero machine changes before the order sheet is approved](#9-plan-first--zero-machine-changes-before-the-order-sheet-is-approved)
- [10. mas 7.x removed the `account` subcommand](#10-mas-7x-removed-the-account-subcommand)
- [11. `say` "succeeds" silently — the assist channel can fail exactly when needed](#11-say-succeeds-silently--the-assist-channel-can-fail-exactly-when-needed)
- [12. Offline-app packages are `.iso` / `.tbz2`, and are never auto-installed](#12-offline-app-packages-are-iso--tbz2-and-are-never-auto-installed)
- [13. Slow remote transfer? It's the link, not the protocol](#13-slow-remote-transfer-its-the-link-not-the-protocol)
- [14. Remote `open` / `say` hit the GUI-session boundary — generate guides locally](#14-remote-open--say-hit-the-gui-session-boundary--generate-guides-locally)
- [15. A blocklisted tap-pathed package appeared in TWO report sections at once](#15-a-blocklisted-tap-pathed-package-appeared-in-two-report-sections-at-once)
- [16. `pgrep -fi <app>` to test "is it running" reports system services, not the app](#16-pgrep--fi-app-to-test-is-it-running-reports-system-services-not-the-app)
- [17. Stubborn apps (ToDesk) survive `rm -rf` — watchdog + launchd + root-owned files](#17-stubborn-apps-todesk-survive-rm--rf--watchdog--launchd--root-owned-files)
- [18. A re-run report dropped finished removals — progress looked like it never happened](#18-a-re-run-report-dropped-finished-removals--progress-looked-like-it-never-happened)
- [19. `brew leaves` hid installed standard tools — they read as "missing" forever](#19-brew-leaves-hid-installed-standard-tools--they-read-as-missing-forever)
- [20. Homebrew now gates untrusted third-party taps — opt the standard's taps through](#20-homebrew-now-gates-untrusted-third-party-taps--opt-the-standards-taps-through)
- [21. A `.pkg`-based cask (tailscale-app) hangs a headless install forever on sudo](#21-a-pkg-based-cask-tailscale-app-hangs-a-headless-install-forever-on-sudo)
- [22. Cask renamed to `-app` suffix read as missing (tailscale → tailscale-app)](#22-cask-renamed-to--app-suffix-read-as-missing-tailscale--tailscale-app)
- [23. mas: stale iWork ids + a localized-name match that never matched](#23-mas-stale-iwork-ids--a-localized-name-match-that-never-matched)
- [24. pnpm globals: bin dir not in PATH, and `ls -g` tree broke collection](#24-pnpm-globals-bin-dir-not-in-path-and-ls--g-tree-broke-collection)
- [25. `pnpm ls -g` is the wrong source of truth — read the shim dir instead](#25-pnpm-ls--g-is-the-wrong-source-of-truth--read-the-shim-dir-instead)
- [26. SUDO_ASKPASS via inline-printf got the password WRONG (escaping hell)](#26-sudo_askpass-via-inline-printf-got-the-password-wrong-escaping-hell)
- [27. Same app in blocklist AND offline-apps → freshly-installed version re-flagged for removal](#27-same-app-in-blocklist-and-offline-apps--freshly-installed-version-re-flagged-for-removal)
- [28. sync-history --delete erased a report generated only on the orchestrator](#28-sync-history---delete-erased-a-report-generated-only-on-the-orchestrator)
- [29. The Ship Report is for the Mac's owner, not the engineer — no jargon](#29-the-ship-report-is-for-the-macs-owner-not-the-engineer--no-jargon)
- [30. Detection logic must stay in lockstep ACROSS scripts — fix collect, fix cleanup too](#30-detection-logic-must-stay-in-lockstep-across-scripts--fix-collect-fix-cleanup-too)
- [31. One tap-qualified formula without its `tap` line aborts the WHOLE bundle](#31-one-tap-qualified-formula-without-its-tap-line-aborts-the-whole-bundle)
- [32. pnpm 12 refuses `add -g` off-PATH, and `pnpm setup` leaves a broken self-shim](#32-pnpm-12-refuses-add--g-off-path-and-pnpm-setup-leaves-a-broken-self-shim)
- [33. Homebrew moves formulas to casks (azure-cli) — the standard goes stale silently](#33-homebrew-moves-formulas-to-casks-azure-cli--the-standard-goes-stale-silently)
- [34. A fresh Mac falls asleep mid-install — background work is not "user activity"](#34-a-fresh-mac-falls-asleep-mid-install--background-work-is-not-user-activity)
- [35. A blank Mac's /usr/bin/python3 is a stub — compare "succeeded" with no report](#35-a-blank-macs-usrbinpython3-is-a-stub--compare-succeeded-with-no-report)
- [36. "Couldn't reach the target" is not "the step finished"](#36-couldnt-reach-the-target-is-not-the-step-finished)
- [37. CLT's softwareupdate label changed shape — match the prefix, not the separator](#37-clts-softwareupdate-label-changed-shape--match-the-prefix-not-the-separator)
- [38. Keychain-backed tools look signed out over SSH](#38-keychain-backed-tools-look-signed-out-over-ssh)
- [39. GUI casks' postflight hangs over SSH — install them inside the GUI session](#39-gui-casks-postflight-hangs-over-ssh--install-them-inside-the-gui-session)
- [40. brew 7 prints `bundle check --verbose` gaps on stderr](#40-brew-7-prints-bundle-check---verbose-gaps-on-stderr)
- [41. Casks get disabled upstream (gas-mask) — remove them from the standard](#41-casks-get-disabled-upstream-gas-mask--remove-them-from-the-standard)
- [42. "Use Chrome for Testing for automation" is advice for tests, not for agents on the web](#42-use-chrome-for-testing-for-automation-is-advice-for-tests-not-for-agents-on-the-web)
- [43. A Mac's Wi-Fi MAC changes when "Private Wi-Fi address" flips — DHCP bindings go stale](#43-a-macs-wi-fi-mac-changes-when-private-wi-fi-address-flips--dhcp-bindings-go-stale)
- [44. The owner's environment is not in the standard — sync it, don't re-type it](#44-the-owners-environment-is-not-in-the-standard--sync-it-dont-re-type-it)
- [45. Remote snippets run in the target's login shell — zsh does not word-split `$var`](#45-remote-snippets-run-in-the-targets-login-shell--zsh-does-not-word-split-var)
- [46. Replacing a SQLite database file: remove its -wal/-shm and wait for the app to exit](#46-replacing-a-sqlite-database-file-remove-its--wal-shm-and-wait-for-the-app-to-exit)
- [47. Switching the Claude provider: what follows by itself and what needs a restart](#47-switching-the-claude-provider-what-follows-by-itself-and-what-needs-a-restart)
- [48. A removal loop fed on stdin stops after the first command that reads stdin](#48-a-removal-loop-fed-on-stdin-stops-after-the-first-command-that-reads-stdin)
- [49. App Store apps are root-owned — `rm -rf` as the user fails](#49-app-store-apps-are-root-owned--rm--rf-as-the-user-fails)
- [50. A freshly installed cask CLI hangs before `main` — syspolicyd is wedged](#50-a-freshly-installed-cask-cli-hangs-before-main--syspolicyd-is-wedged)
- [51. `~/.zshenv` order: Homebrew's PATH before anything that calls a brew tool](#51-zshenv-order-homebrews-path-before-anything-that-calls-a-brew-tool)
- [52. Key-only SSH needs proof of key login — some Macs don't log it](#52-key-only-ssh-needs-proof-of-key-login--some-macs-dont-log-it)
- [53. A person's own Chrome with remote debugging on holds the agent port](#53-a-persons-own-chrome-with-remote-debugging-on-holds-the-agent-port)

</details>

## 1. `defaults write` fails SILENTLY on modern macOS (the #1 trap)

With SIP on and the calling terminal lacking **Full Disk Access**, `defaults write`
returns success but the value lands in a legacy path and never takes effect.
**Countermeasure**: `write_verify` in `lib/idempotent.sh` reads every key back after
writing and records a finding on mismatch. Never write defaults bare. `precheck.sh`
probes for FDA up front (heuristic — the read-back is the real safety net).

## 2. `brew bundle` fails on manually installed apps

`brew bundle install` aborts with "It seems there is already an App at …" when
/Applications has an unmanaged copy of a cask's app.
**Countermeasure**: run `adopt-pass.sh` before bundling — `brew install --cask --adopt`
takes over the existing app losslessly (no re-download, no restart, no data touched).
If versions mismatch, adopt fails → finding for human review. Never `--force` (it overwrites).

## 3. Casks that rename their app on install cannot adopt

Example: the `feishu` cask ships `Lark.app` and renames it to `Feishu.app` during
install. A manually installed `Lark.app` never matches → adopt always fails.
**Countermeasure**: these are delete-and-reinstall migrations:
`rm -rf /Applications/Lark.app && brew install --cask feishu`. User data lives in
`~/Library` and survives. (The intl `lark` cask keeps `LarkSuite.app` and adopts fine.)

## 4. Never uninstall the network transport you are riding

If the session reaches the machine over a VPN/mesh client (e.g. Tailscale),
uninstalling that client cuts your own connection mid-run.
**Countermeasure**: adopt only — adoption transfers package management without
touching the running process. A standalone install and the cask are the same app.

## 5. mas has two hard human breakpoints

- `mas signin` has been disabled by Apple since macOS 10.13 → a new machine must
  sign in to the App Store via GUI first.
- Paid apps must already be owned by the account; mas cannot purchase.
**Countermeasure**: precheck verifies sign-in; mas install failures are findings,
not errors — sign in, re-run the pipeline (re-entry is free).

## 6. symbolichotkeys: never edit the plist, never read it by eye

cfprefsd's cache overwrites direct plist edits; and modifier masks are effectively
unreadable by eye (a Globe-key binding is easily misread as ⌘Space).
**Countermeasure**: write via `defaults write com.apple.symbolichotkeys
AppleSymbolicHotKeys -dict-add`; read via `defaults export | plutil -convert json`
and compare at parameter level; apply with `activateSettings -u`.
The id baseline lives in `standard/hotkeys.tsv`.

## 7. `HOMEBREW_BUNDLE_NO_UPGRADE=1` is mandatory

Homebrew is a rolling release with no lockfile — re-running bundle would upgrade
everything and drift versions across machines.
**Countermeasure**: the pipeline pins it. Upgrading is a separate, deliberate action.

## 8. Cleanup is a high-risk, standalone action

`brew bundle cleanup --force` removes everything not in the Brewfile — including
paid, multi-gigabyte apps that are expensive to reinstall.
**Countermeasure**: the pipeline never removes anything. `cleanup.sh` confirms every
item via tty read. mas-installed apps are removed with `rm` on the .app
(`mas uninstall` needs sudo and is unreliable). App data (e.g. `~/.ollama` models)
is kept by design — programs and data are separate decisions.

## 9. Plan first — zero machine changes before the order sheet is approved

The decision list is *input data* for `standard/`, not a to-do list to hand-execute.
Materialize decisions into the standard, show the user the comparison report, and
only execute what comes back on the approved order sheet.

## 10. mas 7.x removed the `account` subcommand

`mas account` now fails with "Unexpected argument" (Apple removed the private API;
mas dropped the command).
~~Countermeasure: detect sign-in with `[ -n "$(mas list | head -1)" ]`.~~ **Wrong** —
`mas list` lists App Store apps *installed on this Mac*, not sign-in. A signed-in Mac
with no App Store apps yet (or no `mas` installed) prints nothing and was reported as
"not signed in" (2026-10-16: the user was signed in; the real failure was an
unrelated Brewfile entry aborting the whole bundle).
**Countermeasure**: sign-in is not readable from the CLI. A non-empty `mas list` proves
it; an empty one proves nothing, so precheck only notes it. The pipeline asks the
human to check sign-in **only when `brew bundle check --verbose` still lists a missing
`App` entry**, and every bundle failure names the actual missing entries.

## 11. `say` "succeeds" silently — the assist channel can fail exactly when needed

`/usr/bin/say` exits 0 even when the output is muted or at volume 0, and a shell
function named `say` shadows the binary entirely (functions win over PATH) — both
failure modes are invisible to the script.
**Countermeasure**: never name a helper `say` (lib uses `msg`); voice goes through
`speak_audibly`, which reads the volume/mute state first, raises the output to a
floor (`MACOS_SETUP_VOICE_VOLUME`, default 50) for the announcement, then restores
the user's exact setting. Every `assist_notify` also posts a banner notification
(volume-proof), and precheck reports the voice-channel state up front. Remember the
human may simply not be next to the target machine — the log
(`/tmp/macos-setup-assist.log`) is the durable record.

## 12. Offline-app packages are `.iso` / `.tbz2`, and are never auto-installed

The offline app installers you supply yourself ship as disk images (`.iso`) and
archives (`.tbz2`), not `.dmg`. `hdiutil attach` mounts an `.iso` fine, but the
contents vary wildly: a bare `.app`, a nested `.dmg`/`.pkg`, or an app plus a separate
installer — and Gatekeeper blocks first launch regardless. Auto-copying the first
`.app` found is fragile and often wrong.
**Countermeasure**: `stage-offline-apps.sh` does NOT install. It stages the files to the
target's Desktop (`~/Desktop/macos-setup-apps/`) and renders a bilingual HTML guide
from `standard/offline-apps.tsv` (one card per app: what it is + how to install), then
announces by voice. The human installs each one. First-launch "app is damaged" is
just quarantine on downloaded files: `xattr -dr com.apple.quarantine <app>` clears it
(the guide spells this out). Source files live on a network share — mount it and
point `MACOS_SETUP_LOCAL_PKGS` at the mount; the script copies idempotently (rsync).

## 13. Slow remote transfer? It's the link, not the protocol

SMB over a mesh link (Tailscale) crawled at ~7M/min. Switching to rsync over SSH
measured the **same** — because the bottleneck was the client↔server link bandwidth (P2P,
15ms, but ~7Mbps, most likely the file server's home-broadband uplink), not the protocol.
**Countermeasure**: `stage-offline-apps.sh` prefers rsync over SSH (`MACOS_SETUP_PKG_SSH` —
stream + `--partial` + ControlMaster), which is the right transport, but no protocol
beats the physical uplink while data leaves the source network. Diagnose with
`tailscale ping` (direct vs DERP) before blaming the protocol — a fast ping with slow
throughput points at bandwidth, not routing. If it's truly uplink-bound, the only wins
are: change where the data lives, upgrade the uplink, or accept the wait.

## 14. Remote `open` / `say` hit the GUI-session boundary — generate guides locally

A script run over SSH (even inside a remote tmux) is not in the logged-in user's GUI
session, so `open <guide>` and `say` silently no-op (cf. #11, #13). Files still land
correctly, but the "ready" announcement never reaches anyone.
**Countermeasure**: generate the HTML guide in the orchestrating session — `gen-guide.py`
is standalone for exactly this — and `scp` it to the target's Desktop. It shows up
regardless of GUI access AND doesn't wait on the slow package transfer (the small guide
arrives in seconds while the multi-GB images stream separately). Announce completion
through the operator's own channel when the human isn't at the target.

## 15. A blocklisted tap-pathed package appeared in TWO report sections at once

`compare.sh` listed `danielfoehrkn/switch/switch`, `openclaw/tap/wacli`,
`yakitrak/yakitrak/obsidian-cli` under **both** the ⛔ Blocklist (→ remove) and the
Off-standard (→ keep) sections — contradictory verdicts for one package. Root cause: the
off-standard "known" set folded blocklist names in via `short(n)` only, collapsing
`danielfoehrkn/switch/switch` to `switch`; but `cur["formula"]` carries the **full tap
path**, so `full − {short}` never subtracted, and the entry slipped through as a fresh
off-standard extra. A sibling case: a formula sharing a cask's name (`tailscale` formula
vs `cask "tailscale"`) is a type mismatch, not a genuine extra, yet landed in keep too.
**Countermeasure**: the off-standard exclusion set must match a name in **every form it
can appear** — full path AND short segment — and must fold in `std_cask` short names so
same-named formulas don't masquerade as off-standard. Rule of thumb: when one set is
built from short names and the other holds full names, set subtraction silently no-ops —
normalize both sides to the same name forms before differencing. A row with an existing
verdict (blocklist → remove, standard → install) must never also be offered as keep.

## 16. `pgrep -fi <app>` to test "is it running" reports system services, not the app

Before uninstalling, we checked `pgrep -fi Cursor` and `pgrep -fi ToDesk` to warn about
running apps. `Cursor` matched `…/TextInputUIMacHelper.framework/…/CursorUIViewService`
— a macOS text-input XPC service with "Cursor" in its name, nothing to do with the
editor. The editor had already quit; the warning was a false positive, and a naive
`pkill -fi Cursor` would have killed a system service.
**Countermeasure**: to decide whether a GUI app is running, match the app's own binary
path, not a substring of every process: `pgrep -fl "/Applications/<App>.app/Contents/MacOS/"`.
Reserve broad `-fi` matches for diagnosis you eyeball, never for `pkill` targets.

## 17. Stubborn apps (ToDesk) survive `rm -rf` — watchdog + launchd + root-owned files

Removing ToDesk hit three defenses at once: (1) its files are **root:admin** owned, so a
user `rm` fails with `Directory not empty` (it deletes the user-owned leaves, leaves the
root ones, dir won't empty) — looks like a lock, is actually permissions; (2) five
**launchd** jobs (`/Library/LaunchDaemons/com.youqu.todesk.*`, `/Library/LaunchAgents/…`)
respawn the service the instant you kill it; (3) deleting `.app` triggers a
**ToDeskUninstaller watchdog** that relaunches from `/Library/Application Support/Todesk/`.
A plain `rm -rf /Applications/ToDesk.app` is necessary but nowhere near sufficient.
**Countermeasure** — order matters: bootout the launchd jobs (`launchctl bootout` user +
system) and delete their plists FIRST so nothing respawns, THEN `sudo pkill -9` the
service, THEN `sudo rm -rf` the app, then sweep `/Library/Application Support/<vendor>/`
and any `/Library/Audio/Plug-Ins/HAL/*.driver` it dropped, then `kill coreaudiod` so a
loaded audio driver actually unloads (the file is gone but coreaudiod still holds the
instance until restarted; launchd brings a clean one back). The blocklist `app` row only
does `rm -rf /Applications/<n>.app` — for service-class software that's step 4 of 6.
Detect this class by checking for vendor launchd jobs before removal; when present, run
the full teardown, not the bare `rm`.

## 18. A re-run report dropped finished removals — progress looked like it never happened

After removing 25 blocklisted items, re-running `compare.sh` to refresh the report made
the removals section **disappear entirely** — the items were gone from the machine, so the
present-only loop emitted no rows. The user couldn't tell "this run removed 25 things" from
"there was never anything to remove": the progress trail evaporated. Then the naive fix —
emit a row for every blocklist entry regardless — went the other way, marking all ~95
blocklist entries `removed ✓`, including dozens the machine **never had**, inflating the
accomplishment.
**Countermeasure**: finished work must persist in the report with a terminal state, but
only what THIS run actually did. compare reads an **execution ledger**
(`raw/macos-setup-executed-<host>.tsv`) that `cleanup.sh` appends to on each successful
removal. A blocklist item that's absent shows `removed ✓` *only* if it's in the ledger;
absent-and-not-in-ledger means never-installed and is omitted. Same principle as install
rows persisting as `ok`: a report re-run mid-setup is a progress ledger, not a fresh
snapshot — terminal states stay, but a machine's prior state is never claimed as your work.
Corollary: removals performed outside `cleanup.sh` (e.g. a hand-run teardown of a stubborn
app, #17) aren't in the ledger — append them by hand or the refreshed report under-reports.

## 19. `brew leaves` hid installed standard tools — they read as "missing" forever

The CLI section showed `go`, `python@3.13`, `ffmpeg` as missing right after a successful
install that had just put them on the machine (read-back confirmed `/opt/homebrew/bin/go`
etc.). Root cause: `collect.sh` snapshotted installed formulas with `brew leaves`, which
lists ONLY top-level formulas — not ones pulled in as another formula's dependency. Those
three got installed as deps of other standard tools this run, so they dropped out of
`leaves` and compare judged them un-installed. The report would never converge: every
re-run re-proposes installing them (idempotent, harmless, but the progress view lies).
**Countermeasure**: collect BOTH views — `formula` (= `brew list --formula`, ALL installed
incl. deps) for "is this standard item present?", and `formula-leaf` (= `brew leaves`) for
"is this an off-standard EXTRA?". Presence checks must use the full list; the leaves list
is only to keep the off-standard section from drowning in dependency noise. Note the name
formats differ — `brew list --formula` emits short names (`peekaboo`), `brew leaves` emits
full tap paths (`steipete/tap/peekaboo`) — so compare on the short segment when crossing
between them.

## 20. Homebrew now gates untrusted third-party taps — opt the standard's taps through

Installing from `steipete/tap` and `antoniorodr/memo` started printing a tap-trust warning
("Untap them with… / To keep allowing them: export HOMEBREW_NO_REQUIRE_TAP_TRUST=1 … will
be removed in a later release"). Today it's a warning and installs still proceed; a future
Homebrew will turn it into a hard prompt — fatal to a non-interactive pipeline.
**Countermeasure**: the standard's taps are vetted, so `pipeline.sh` exports
`HOMEBREW_NO_REQUIRE_TAP_TRUST=1` scoped to the bundle step (not the user's global shell)
so bundle installs don't block. This is a deliberate, narrow trust grant for known taps —
do NOT set it globally or as a blanket default; if the standard ever adds an unfamiliar
tap, that's a decision to make in `standard/`, not something to silently wave through.

## 21. A `.pkg`-based cask (tailscale-app) hangs a headless install forever on sudo

`brew install --cask tailscale` ran fine until the pkg artifact: `==> Running installer
for tailscale-app with sudo (which may request your password)...` — then sat for 18
minutes with no tty to type into. A cask whose artifact is a `.pkg` (not a plain `.app`)
shells out to `/usr/sbin/installer` under sudo; in a background tmux over SSH there's no
terminal, so it blocks indefinitely AND stalls every cask queued behind it. (`echo pw |
tmux new-session` does NOT help — tmux reopens its own tty and the pipe never reaches the
script's `read`.)
**Countermeasure**: for unattended GUI installs, give sudo a non-interactive source via
`SUDO_ASKPASS` — write a 0700 askpass script that echoes the password (fed from a 0600
file scp'd over, deleted on first read), `export SUDO_ASKPASS`, `sudo -A -v` to prime the
credential cache, then run the casks; brew's pkg installer inherits the cached sudo. Always
delete the askpass on EXIT (trap) and the password file the instant it's read. Know which
casks are pkg-based before a headless run (tailscale, some VPN/driver apps) — they're the
ones that need this; pure `.app` casks don't touch sudo. Better still, when the operator is
reachable, surface a voice/banner breakpoint and let them approve sudo at the target.

## 22. Cask renamed to `-app` suffix read as missing (tailscale → tailscale-app)

The standard names `cask "tailscale"`, but Homebrew renamed it to `tailscale-app`, and
`brew list --cask` reports the installed name `tailscale-app`. So `has("cask","tailscale")`
returned false right after a successful install — compare judged it missing, would
re-propose installing forever, and worse, kept nudging a reinstall of the one cask pitfalls
#4 says must NEVER be reinstalled (it's the mesh transport). Same shape as #19: collected
name ≠ standard name.
**Countermeasure**: `has_cask(n)` matches `n` OR `n-app`, and the off-standard filter
de-suffixes `-app` before deciding a cask is an extra. As Homebrew migrates more casks to
the suffix, this absorbs them without per-cask edits. If a rename ever changes more than the
suffix, fix it in `standard/` (write the real cask token), don't pile on special-cases.

## 23. mas: stale iWork ids + a localized-name match that never matched

App Store (Step 4) showed Pages as missing on a machine where Pages 15.2.1 was plainly
installed. Two independent bugs stacked:
(a) **Stale ids** — the standard listed iWork as `Pages 409201541` / `Keynote 409183694`
/ `Numbers 409203825`, but Apple migrated iWork to the 3613xxxxx id range; the old ids now
return nothing from `mas info`, so `mas install` would fail and compare's id never matched
what's installed. Fixed the three ids in Brewfile.standard (verified via `mas info`).
(b) **Broken collect + localized names** — collect.sh's single greedy sed over `mas list`
mis-parsed multi-space / non-ASCII rows and emitted the whole raw line as the "name", and
even when parsed the name is *localized* (the App Store shows the translated app name on a
non-English machine), so matching the standard's English "Pages" was hopeless.
**Countermeasure**: collect emits BOTH `mas\t<name>` and `mas-id\t<id>` (robust field
parse, then trim); compare matches by **id first** (stable, locale-independent), name and
.app presence only as fallbacks. Lesson that recurs (cf. #19 leaves, #22 cask -app): match
on the stable identifier the tool actually stores, never on a display string that varies by
locale or Homebrew renames — and re-verify vendored ids periodically, they rot.

## 24. pnpm globals: bin dir not in PATH, and `ls -g` tree broke collection

Installing the 5 Node globals surfaced two problems:
(a) **PNPM_HOME/bin not in PATH** — `pnpm add -g` refused with "global bin directory
…/pnpm/bin is not in PATH". The machine's `.zshenv` exported `PATH="$PNPM_HOME:$PATH"`
(the dir itself), but pnpm 11.x puts shims in `$PNPM_HOME/bin`. The legacy layout also had
loose executables (ccline, mcporter…) directly in `$PNPM_HOME`, so the fix was to prepend
BOTH `$PNPM_HOME/bin` (new shims) AND keep `$PNPM_HOME` (legacy tools) — dropping the old
path would orphan those. `.zshenv` is the user's dotfile: back it up first, edit narrowly.
(b) **`pnpm ls -g` collection found nothing** — pnpm 11.x renders globals as a UTF-8 box
tree (`├── pkg@ver`); collect.sh's `grep '^[a-z@]'` matched zero lines, so every global
read as missing forever. Fixed by parsing `pnpm ls -g --json` and emitting the package
NAMES (incl. scoped `@openai/codex`) — which is what compare matches against node-globals'
pkg column. Fourth instance of the same lesson (cf. #19/#22/#23): parse the tool's machine
output (--json), never its human/tree rendering, and match on the identifier it stores.

## 25. `pnpm ls -g` is the wrong source of truth — read the shim dir instead

Collecting pnpm globals via `pnpm ls -g` failed twice over: (a) it needs node, which is
fnm-managed and absent from collect's non-interactive `bash -lc` PATH ("env: node: No such
file or directory" → empty); and (b) even with node present, `pnpm ls -g`'s answer depends
on the active node major — this machine had TWO global stores (`global/5` and `global/v11`
from different node versions), and `add -g` wrote to v11 while the default node reported 5.
So packages that were installed, with working shims, read as "missing", and a global in the
*other* store (openclaw) even leaked into the blocklist's remove list. Three+ regenerations
chased this in circles.
**Countermeasure**: don't ask `pnpm ls` what's installed — list `$PNPM_HOME/bin`. Those
shims are the ground truth for "which global commands actually run" (store-agnostic,
node-agnostic, no node process needed), and they're exactly node-globals.txt's first column
(the bin name). collect emits `pnpm-g\t<binname>`; compare matches the bin column first.
Lesson, fifth time over (cf. #19/#22/#23/#24): match on the artifact that proves the thing
works — here the executable shim — not a query whose result shifts with ambient state.
Side note: the install half had its own trap — `pnpm add -g` needs `$PNPM_HOME/bin` in PATH
and, on a legacy layout, both `$PNPM_HOME/bin` (new shims) and `$PNPM_HOME` (old loose
binaries) so existing tools aren't orphaned; edit the user's dotfile narrowly, back it up.

## 26. SUDO_ASKPASS via inline-printf got the password WRONG (escaping hell)

The first headless-sudo attempts failed with "Sorry, try again" — not because askpass was
the wrong approach (#21), but because the askpass *script body* was built with a nested
`printf '...%s...' "$PW"` inside a `ssh bash -lc "..."` inside a parent shell. Three layers
of quoting mangled the password before it reached sudo. Verified by checking only the
LENGTH of the askpass output (never echo the secret): it didn't match.
**Countermeasure**: don't synthesize the askpass script with interpolation across SSH
layers. scp two plain files instead: a fixed askpass `#!/bin/sh\ncat /tmp/.pwfile` (0700)
and the password file (0600), `export SUDO_ASKPASS=/path/askpass`, `sudo -A -v` to prime,
then `sudo -n …` for each privileged call; delete both files immediately after. Also: the
sudo credential cache did NOT carry into child `bash "$d"` subprocesses the way expected, so
prime with `-A -v` in the same shell that runs the privileged commands, or pass askpass
through. Always sanity-check by length, and read the value back (pmset AC sleep → 0).

## 27. Same app in blocklist AND offline-apps → freshly-installed version re-flagged for removal

After the user hand-installed Proxyman 6.10.0 (an offline-apps app), Step 1 (removals)
re-listed `Proxyman` as "to remove". Root cause: `app Proxyman` was in blocklist.txt (to purge
an OLD manually-installed copy) while `Proxyman` is also an offline-apps standard app (the build
you supply yourself). The blocklist `app` row matches by /Applications name prefix, so it flagged
the brand-new install. (Permute didn't collide only because its blocklist row was version-pinned
`Permute 3` vs the installed `Permute 4` — luck, not design.)
**Countermeasure**: an app the standard WANTS (offline-apps or Brewfile) must not also sit in the
blocklist — that's a self-contradicting standard. Removed `app Proxyman`. Better: compare should
defensively suppress any blocklist row whose name also appears in offline-apps.tsv / the Brewfile and
log it, so a future overlap can't silently re-propose deleting a standard app (cf. #15 — the
same app surfacing in two sections with contradictory verdicts). When a blocklist
entry exists to kill an *old* build that an offline-apps entry now supersedes, version-pin it (`Permute 3`)
or drop it once the old build is gone — don't leave a bare name that catches the new one too.

## 28. sync-history --delete erased a report generated only on the orchestrator

The Ship Report was generated into the orchestrator's local `.history/.../artifacts/`, then
the next `sync-history.sh` run (which rsyncs target→orchestrator with `--delete`) wiped it —
the file didn't exist on the target, so `--delete` removed it locally to mirror. Anything
created only on the orchestrator side is fugitive under a mirroring pull.
**Countermeasure**: treat the TARGET's `.history` as the authoritative copy. Generate or
place run artifacts there first (scp/cp into the target's dir), THEN sync back — the pull
brings them home and `--delete` leaves them alone because both sides agree. Equivalently,
the orchestrator could generate locally and push to the target before the next pull. Either
way: don't leave a one-sided artifact in the path of a `--delete` mirror.

## 29. The Ship Report is for the Mac's owner, not the engineer — no jargon

The first Ship Report headlined the machine as "converged to standard" and was full of
internal terms: "blocklist", "read-back", "pitfalls/skill notes", "brew formula/cask/mas",
"run record", "pending". A normal Mac user reads none of that. The report is a deliverable
FOR THE PERSON WHO USES THE MACHINE, not a build log.
**Countermeasure**: gen-ship-report.py speaks plain language — "your <nickname> is ready to
use / everything's set". Step titles map through `friendly_step()` (brew formula →
"command-line tools", cask → "desktop apps", mas → "App Store apps", baseline → "system
settings"). Metrics read "apps installed / apps removed / settings adjusted / every item
verified", not "removed/installed/baseline/pitfalls". The engineering traps become "small
things handled for you" in lay terms, no pitfall numbers. The report ships in the user's
language (the UI strings are localized in `gen-ship-report.py`); narrative.json carries a
`nickname` (e.g. "Office Mac mini") so the hero isn't a hostname. Keep the technical run
record (TIMELINE/CHANGELOG/REPORT/pitfalls) for ourselves; the Ship Report is the only
artifact a non-engineer sees — write it for them.

## 30. Detection logic must stay in lockstep ACROSS scripts — fix collect, fix cleanup too

A code review caught that after collect.sh switched pnpm-globals to read `$PNPM_HOME/bin`
shims (#25) and compare.sh added `has_cask` for `-app` aliases (#22), **cleanup.sh still
used the OLD detection** — `pnpm ls -g` for pnpm-g, exact-match for casks. So a blocklisted
pnpm global or a renamed cask that IS present would be judged absent and silently skipped by
cleanup. The collection/match fix only landed in two of the three scripts that need it.
**Countermeasure**: presence detection for each artifact kind (formula / cask / app / pnpm-g
/ uv-tool / local-bin) appears in collect.sh, compare.sh AND cleanup.sh — when you change how
one decides "is this installed", grep the others for the same kind and update in lockstep.
cleanup now mirrors: cask matches `<name>|<name>-app`, pnpm-g checks `$PNPM_HOME/bin/<name>`.
General rule: a detection rule duplicated across N scripts is N places to keep honest; a
shared helper would be better, but until then, a cross-script grep is mandatory after any
collection change.

## 31. One tap-qualified formula without its `tap` line aborts the WHOLE bundle

`brew "joshmedeski/sesh/sesh"` had no `tap "joshmedeski/sesh"` line. Every machine that
had been set up before already had the tap, so it never showed. On a Mac that had never
seen it (2026-10-16) `brew bundle` stopped at "No available formula … requires the tap" and
**installed nothing after it** — 38 entries, pnpm included.
**Countermeasure**: every `owner/tap/formula` line needs its `tap "owner/tap"` line; an
entry nothing depends on any more (sesh, retired from the shell setup) leaves the standard.
Validate on a machine that has never seen the tap, not on one already set up.

## 32. pnpm 12 refuses `add -g` off-PATH, and `pnpm setup` leaves a broken self-shim

pnpm 12 (global dir `~/Library/pnpm/bin`) fails every `pnpm add -g` with
`ERR_PNPM_GLOBAL_BIN_DIR_NOT_IN_PATH`. Running `pnpm setup` fixes `.zshrc` but also drops
`pnpm`/`pn`/`pnpx`/`pnx` shims there that `exec` a `global/v11/…/pnpm` that was never
installed — they sit first on PATH, so every pnpm call then fails.
**Countermeasure**: the pipeline exports `PNPM_HOME` + both bin dirs for its own run and
never calls `pnpm setup`; your shell config (`~/.zshenv`) must put the dir on the
non-interactive PATH, and the pipeline reports a finding when it is missing there.

## 33. Homebrew moves formulas to casks (azure-cli) — the standard goes stale silently

Homebrew 7 migrated `azure-cli` from homebrew/core to a cask. Machines that installed the
formula earlier keep it, so nothing looks wrong — until a new Mac reads "No available
formula with the name azure-cli". **Countermeasure**: when bundle warns "migrated from
homebrew/core to homebrew/cask", change the entry to `cask` in the standard (one line).

## 34. A fresh Mac falls asleep mid-install — background work is not "user activity"

A new Mac mini ships with system sleep = 1 minute after the display sleeps. A long
`brew bundle` started over SSH does not count as activity, so the target idle-sleeps
mid-run: Wi-Fi stays associated, ARP goes unanswered, SSH reports "Host is unreachable",
and Wi-Fi wake packets don't get through (2026-10-19). **Countermeasure**:
`pipeline.sh` holds `caffeinate -i -w $$` for the whole run, `remote.sh` wraps every step
in `caffeinate -i`, and an agent-node writes its pmset baseline at step 0, not step 6.

## 35. A blank Mac's /usr/bin/python3 is a stub — compare "succeeded" with no report

Before Xcode CLT exists, `/usr/bin/python3` pops the CLT install dialog and fails. compare.sh
used it to render the report and still exited 0 in silent mode — a run that produced
nothing looked like a pass. **Countermeasure**: compare refuses on a blank Mac and points
to `pipeline.sh --prereqs-only` (CLT + Homebrew, identical on every Mac); it also fails if
the report file is missing after rendering.

## 36. "Couldn't reach the target" is not "the step finished"

The first remote.sh treated any non-zero ssh exit as "the run ended", so a sleeping target
ended the wait with `exit unknown`. **Countermeasure**: ssh exit 255 means *we could not
ask* — keep waiting, say so once, and give up loudly after 10 minutes with a pointer to
`--status`. Never fold "not probed" into a verdict (agent-ready's `unknown` is the same rule).

## 37. CLT's softwareupdate label changed shape — match the prefix, not the separator

`ensure_clt` matched `Command Line Tools for Xcode-<ver>`; macOS 27 lists
`Command Line Tools for Xcode 27.0-27.0` (space, not hyphen) and the headless install found
nothing (Homebrew's installer then installed CLT itself, masking it). **Countermeasure**:
match `^\* Label: Command Line Tools.*` and take the highest with `sort -V`.

## 38. Keychain-backed tools look signed out over SSH

`claude`, `gh` and anything else storing tokens in the login keychain fail from an SSH
session even when signed in at the console — the SSH process is outside the GUI security
session. Reading that as "not signed in" sends a human to re-login for nothing; reading it
as "fine" lets dispatched agents fail. **Countermeasure**: agent-ready starts a tmux server
inside the GUI session (LaunchAgent `com.macos-setup.agent-tmux`) and probes keychain tools
*inside it*; without it, an SSH-side failure is `unknown`, never `fail` or `pass`.

## 39. GUI casks' postflight hangs over SSH — install them inside the GUI session

`orbctl _internal brew-postflight` (OrbStack's cask postflight) needs the GUI session; started
from SSH it waits forever and the whole `brew bundle` sat on it for 26 minutes
(2026-10-19). **Killing it is wrong**: brew then treats the cask as failed and *rolls back*,
deleting OrbStack.app that had already been copied. **Countermeasure**: install such casks
inside the GUI-session tmux server (agent-ready `tmux-gui-server`):
`tmux new-window -t agent-home "brew install --cask orbstack"` — the postflight completes
(and any dialog appears on the target's screen, where a human can click it).

## 40. brew 7 prints `bundle check --verbose` gaps on stderr

The pipeline counted missing entries with `brew bundle check --verbose … 2>/dev/null | grep '^→'`
and reported "0 missing" while orbstack and gas-mask were absent — brew 7 writes the `→` lines
to stderr. **Countermeasure**: `2>&1` before the grep. A count of 0 next to "not satisfied"
is a contradiction — treat it as a broken probe, never as a pass.

## 41. Casks get disabled upstream (gas-mask) — remove them from the standard

Homebrew disables casks that stop passing Gatekeeper (`gas-mask`, 2026-09-01). Existing
machines keep the app, a new Mac can never satisfy the bundle. **Countermeasure**: on
"has been disabled", drop the line from `Brewfile.standard` with a dated comment; renames
("tailscale was renamed to tailscale-app") get the new name the same day.

## 42. "Use Chrome for Testing for automation" is advice for tests, not for agents on the web

Google recommends Chrome for Testing for automation because it pins versions. An agent
browsing real sites needs to look like a visitor instead: CfT reports Client Hints brands
`Chromium` only (no `Google Chrome`), shows a permanent "for testing" infobar (viewport
937 vs 1217px on the same screen) and can't sync a Google account. **Countermeasure**: the
real Google Chrome with a dedicated `--user-data-dir` — Chrome 136's debugging-port block
applies only to the default profile (2026-10-19).

## 43. A Mac's Wi-Fi MAC changes when "Private Wi-Fi address" flips — DHCP bindings go stale

A reboot or toggling the setting swaps between the hardware MAC and a private one (and
back), and a router binding on one MAC silently stops applying.
**Countermeasure**: bind the fixed IP to BOTH MACs (OpenWrt `dhcp.@host[].mac` takes a list),
and set the network's private address to Off or Fixed.

## 44. The owner's environment is not in the standard — sync it, don't re-type it

Brewfile + defaults + agent-ready make machines *equal*; they do not carry the owner's Claude
settings/agents/plugins/user MCP servers, personal `.zshrc`, or CC Switch providers. Doing that
by hand on a new agent node took an hour and missed things twice (plugins, user MCP servers).
**Countermeasure**: `scripts/sync-user-env.sh <target>` from the owner's main Mac. Per-machine
choices are kept: settings hooks, the API provider in `env`, the CC Switch current provider.

## 45. Remote snippets run in the target's login shell — zsh does not word-split `$var`

`for row in $cur` iterated once over the whole multi-line string under zsh, so "keep the current
provider" silently did nothing. **Countermeasure**: in snippets sent over SSH use
`printf '%s\n' "$x" | while IFS=… read -r …` (or run them with `bash -c`), never `for … in $x`.

## 46. Replacing a SQLite database file: remove its -wal/-shm and wait for the app to exit

An app that flushes on quit, or a leftover `*.db-wal`, can replay old state into the new file.
**Countermeasure**: quit the app and poll until its process is gone, `rm -f x.db-wal x.db-shm`,
then `mv` the new file in; read the result back.

## 47. Switching the Claude provider: what follows by itself and what needs a restart

`scripts/claude-channel.sh <target> <provider>` switches a Mac's channel without the GUI
(quits CC Switch, merges the provider's `env` into `~/.claude/settings.json`, sets the DB's current
provider, reopens the app, reads it back). With cc-moss 0.3.1+ Moss keeps its own copy of the
provider and follows within a second; running sessions take a new address/token on their next
message. **A switch they cannot take in** — back to "Claude Official", or a provider that sets
`ANTHROPIC_MODEL` — needs `cc-moss restart --stale`. API-token providers disable claude.ai
connectors (and computer use) for those sessions.

## 48. A removal loop fed on stdin stops after the first command that reads stdin

`grep … | while read …; do brew uninstall …; done` removed 19 of 41 items: one cask's uninstall
hook read stdin and swallowed the rest of the list, and the loop ended "successfully".
**Countermeasure**: the list comes on fd 3 (`while read … <&3; do …; done 3< <(…)`) and every
command in the body gets `</dev/null`; `tests/test_cleanup.sh` guards both.

## 49. App Store apps are root-owned — `rm -rf` as the user fails

**Countermeasure**: `cleanup.sh` falls back to `sudo -n rm -rf` and confirms the bundle is gone.

## 50. A freshly installed cask CLI hangs before `main` — syspolicyd is wedged

The 1password-cli cask's postflight (`op completion bash`) hung for hours; even `op --version`
never returned and `sample` showed it parked at `_dyld_start`. Other new binaries ran fine,
and clearing the quarantine xattr did not help. The Gatekeeper assessment never finished.
**Countermeasure**: `sudo killall syspolicyd` (launchd restarts it); the binary then runs and
brew continues. Diagnose with `sample <pid>`: a process at `_dyld_start` is waiting on the system.

## 51. `~/.zshenv` order: Homebrew's PATH before anything that calls a brew tool

One `~/.zshenv` block ran `command -v fnm && eval "$(fnm env)"` before the block that put
`/opt/homebrew/bin` on PATH, so `ssh host cmd` saw no node/npx (an interactive shell hid it).
**Countermeasure**: the block that adds Homebrew's PATH comes first; anything that calls a brew tool
comes after it.

## 52. Key-only SSH needs proof of key login — some Macs don't log it

`session_used_pubkey` looks for sshd's "Accepted publickey … port N"; on some Macs the unified log
has no such line, so the apply refuses (correctly: no proof, no lock). **Countermeasure**: prove it
from the orchestrator — `ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no
-o BatchMode=yes <host> true` — then apply with `AR_PUBKEY_VERIFIED=1`, and check a password login
is now refused.

## 53. A person's own Chrome with remote debugging on holds the agent port

Chrome's "allow remote debugging" (`chrome://inspect/#remote-debugging`) makes a person's
everyday Chrome listen on 9222. An agent's browser setup then refuses, and changing the workspace's
port only moves the clash onto another workspace's. **Countermeasure**: untick it (or quit that
Chrome); ports stay fixed per workspace on every Mac.
