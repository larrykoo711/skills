---
name: macos-setup
version: 0.2.0
description: One-stop, standard-driven macOS machine setup — Homebrew formulas and casks, App Store apps, Node/Python globals, system defaults, keyboard shortcuts, security and power baseline. Use when setting up a new Mac from scratch, onboarding a fresh macOS machine, converging an existing Mac to the standard, auditing drift from it, making a Mac Agent Device Ready (always-on, headless, agent-driven node), or updating the standard itself (macos setup, 装机, 新 Mac 配置, 一键装机, 对标标准, 收敛漂移, agent-ready, agent node, 无人值守 Mac). Not for one-off package installs, macOS version upgrades, or MDM-managed fleets — those have their own tooling.
---

# macOS Setup

**Declare your Mac once. Converge any Mac to it.**

`standard/` is the single source of truth for what a machine should be; the scripts
are the engine that gets it there: a read-only audit, an interactive decision report,
and an idempotent pipeline with explicit human checkpoints where automation cannot go
(App Store sign-in, sudo, Full Disk Access, bring-your-own app installers).

Three guarantees:

1. **Read-only until approved** — nothing touches the machine before the user pastes
   back an approved order sheet.
2. **Every write is verified** — defaults are read back after writing (they can fail
   silently), bundles are checked, hotkeys are re-exported and compared.
3. **Idempotent** — re-run the pipeline any time; satisfied steps cost nothing, so
   human breakpoints never block the rest.

## When to use

- A brand-new (blank) Mac that must reach the standard
- An existing Mac that drifted — audit it, then converge
- "How far is this machine from the standard?" — run Step 2 only
- Changing the standard itself — edit `standard/`, then regenerate reports

**Not for**: one-off installs (`brew install` it), macOS version upgrades,
or MDM-managed fleets with their own tooling.

## Quick start (from the skill directory)

```bash
bash scripts/task-init.sh <host>   # Step 0 — create .history/<host>/<date>-setup/ run record
bash scripts/precheck.sh    # Step 1 — prerequisites (read-only)
bash scripts/compare.sh     # Step 2 — decision report → Desktop + browser + voice ping
# … user annotates the report, clicks "Copy for Claude Code", pastes it back …
bash scripts/pipeline.sh --exclude-file /tmp/macos-setup-exclude.txt   # Step 3
```

## A blank Mac, driven from another Mac (the field-tested order)

```bash
bash scripts/agent-bootstrap.sh --pubkey ~/.ssh/<key>.pub --remote user@<ip> [--jump <router>]
bash scripts/remote.sh <host> <target> precheck
bash scripts/remote.sh <host> <target> pipeline --prereqs-only   # CLT + Homebrew: compare needs them
bash scripts/remote.sh <host> <target> compare                    # open the synced HTML locally
bash scripts/remote.sh <host> <target> pipeline [--profile agent-node] --exclude-file <file>
```

Then, from the owner's main Mac, carry over what the standard does not (Claude settings, agents,
plugins, user MCP servers, personal `.zshrc`, CC Switch providers — per-machine choices kept):

```bash
bash scripts/sync-user-env.sh <target> [--dry-run] [--only claude,claude-md,zshrc,cc-switch]
bash scripts/claude-channel.sh <target> --list | "<provider name>"   # switch its CC Switch provider headless
```

Opt-outs are env vars (`SYNC_SKIP_COMMANDS`, `SYNC_SKIP_MCP`, `SYNC_ZSHRC_MANAGED_TAG`) —
see the script header.

`remote.sh` runs every step detached under `caffeinate -i` (a fresh Mac idle-sleeps after
~1 min) and treats "can't reach the target" as *still running*, never as done. GUI casks
whose postflight needs the console (OrbStack) belong in the GUI-session tmux — pitfalls #39.

## Agent-node profile (Agent Device Ready)

For a Mac that agents drive with nobody in front of it (always-on build/agent box),
add `--profile agent-node` to the pipeline. It converges `standard/agent-ready.tsv`
on top of the normal standard: key-only SSH, NOPASSWD sudo, non-interactive PATH,
Tailscale, never-sleep + auto-restart, no surprise OS-update reboots, FileVault kept
on (SSH pre-boot unlock), a tmux server inside the GUI session so dispatched agents can
use the keychain, and signed-in claude / gh / git / docker. The profile is remembered
(`~/.config/macos-setup/profile`), so later `verify.sh` runs include the layer.

```bash
bash scripts/agent-bootstrap.sh --pubkey ~/.ssh/<key>.pub   # Day-0: paste the output on the new Mac
bash scripts/remote.sh <host> <ssh-target> pipeline --profile agent-node
bash scripts/remote.sh <host> <ssh-target> agent-ready --check   # pass · fail · manual · unknown
```

Verdicts are four-way and `unknown` is never a pass. Lifecycle, rationale and the
FileVault / keychain decisions: [references/agent-ready.md](references/agent-ready.md).

## Step 1 — Precheck

`scripts/precheck.sh` verifies macOS version, disk, network, sudo, **Full Disk
Access**, **App Store sign-in**, Xcode CLT. Levels: `block` (fix before anything,
exits 1) · `manual` (human breakpoint — the pipeline reminds by voice when it gets
there) · `info` (be present at execution time; not a gate).

## Step 2 — Compare (interactive decision report)

`scripts/compare.sh` writes `~/Desktop/macos-setup-playground-<host>.html` on the
target, opens it in the default browser, and asks for the user's attention by voice.

- **Numbered phases**: each module carries a step badge — Prerequisites is ⓪, content
  modules count ①..⑧ in execution order (removals → CLI → GUI → App Store → globals →
  baseline → offline → off-standard). The badge goes green when that phase has no pending
  work left, so the report reads as a progress tracker: which step you're on, what's done.
- **Prerequisites are the first module**: any `block`/`manual` item locks every other
  section until fixed and the report regenerated.
- Pending items **default to approved**; each row can be rejected or annotated.
- **Off-standard rows** (present here, not in the standard) decide **keep vs remove**
  — default keep; recurring keeps are candidates for the standard.
- Each module has a Pending/All pill switch (compliant rows hidden by default) and
  its own **Copy for Claude Code** export.
- **Bilingual UI (English / 中文)**: follows the browser language automatically; a
  capsule switch (🌐 EN | 中文, sliding thumb) in the corner overrides it, and the
  choice persists. The exported order sheet is **always English** — a stable
  contract for the executor.
- Env overrides: `MACOS_SETUP_OUT=<path>`, `MACOS_SETUP_SILENT=1` (no browser/voice —
  for tests and remote orchestration).

While waiting for the pasted order sheet, poll periodically; on each empty poll call
`assist_remind_or_silent` (lib) — **at most 3 voice reminders, then wait silently**.

## Step 3 — Pipeline (when the order sheet arrives)

The order sheet contract — handle each section exactly like this:

| Order sheet section | What to do |
|---|---|
| ✅ Approved | Covered by the pipeline run below |
| ⛔ Rejected — skip | Copy each line's leading token **verbatim** into `/tmp/macos-setup-exclude.txt` |
| 🗑 Off-standard — removal | **Not** in the pipeline: run each listed command one at a time, confirming each |
| 📦 Off-standard — keep | Do nothing |

Exclude tokens: bare names skip packages (bundle / pnpm / uv); namespaced tokens
(`default:<domain>.<key>`, `hotkey:<id>`, `security:<name>`, `power:ac-sleep`) skip
individual baseline writes — the defaults scripts honor them via `MACOS_SETUP_EXCLUDE`.

**Removals go first.** When the order sheet approves any removals, run `cleanup.sh`
*before* `pipeline.sh` — clearing rejected items before installing keeps the new setup
from picking up a dependency on something about to be deleted (a shell plugin, a CLI
another formula shims to, an app a cask links against). The compare report orders the
removals section first and banners this for the same reason. Removal is still one
y/N per item — `cleanup.sh` never batch-removes.

```bash
# 1) removals first (only if the order sheet approved any) — one y/N per item
bash scripts/cleanup.sh --exclude-file /tmp/macos-setup-exclude.txt
# 2) then converge onto the clean base
bash scripts/pipeline.sh --exclude-file /tmp/macos-setup-exclude.txt
```

Pipeline order: Homebrew → **adopt pass** (lossless takeover of manually installed
apps) → `brew bundle` (`NO_UPGRADE=1`) → pnpm globals → uv tools → Claude Code →
defaults / shortcuts / security / power baseline (**write + read-back**) → stage
offline installers to the Desktop (bilingual guide; the human installs them) → `verify.sh`.

`cleanup.sh` is still gated on explicit approval — it removes nothing the order sheet
didn't approve, and skips everything in the exclude file.

**After each execution phase, re-run `compare.sh` to refresh the report.** The report is
a snapshot from when it was generated — it does NOT update itself as you remove or install.
Re-running compare is free (idempotent, read-only) and is the progress view: the next
pending section rises to the top, and **finished work stays visible with a terminal state**
rather than vanishing — installed targets read `ok`, removed blocklist items read
`removed ✓`. A done item is dimmed, has no decision control, and is hidden in the Pending
view but shown in All. Without this the user reopens a stale report still showing "25 to
remove" long after they're done, and can't tell what's left vs what was accomplished.
So: run a phase → `compare.sh` → `sync-history.sh` → the refreshed report is the progress
ledger. (Operator at another Mac: regenerate with `MACOS_SETUP_SILENT=1`, re-open the
synced copy locally — see Local vs remote.)

How `removed ✓` is distinguished from never-installed: an **execution ledger**
(`raw/macos-setup-executed-<host>.tsv`, `<action>\t<type>\t<name>` per line) records what
this run actually did. `cleanup.sh` appends one line per successful removal; compare reads
it. A blocklisted item that's absent AND in the ledger shows `removed ✓`; absent and not in
the ledger means the machine never had it — not this run's result, so it's not shown.
(Removals done by hand outside `cleanup.sh` won't be in the ledger — append them so the
report reflects reality.)

Finish by writing the convergence checklist into the run's `REPORT.md` (see Run records
below): every item ✅/❌ with the command and read-back value.

## Run records — `.history/<host>/` (every run is logged for replay)

Each run gets a gitignored directory `.history/<host>/<date>-setup/`, seeded by
`scripts/task-init.sh <host>` from `templates/task/`. One dir per device per run — a
device's setup history sits beside its other records and travels with the device:

- **TIMELINE.md** — every step, timestamped (the *process*)
- **CHANGELOG.md** — actual machine changes with read-back values (the *ledger*)
- **REPORT.md** — convergence report + retrospective (the *summary*; feeds pitfalls.md)
- `artifacts/` — generated HTML / order sheet / exclude / install guide · `raw/` — collection & logs

Keep them current as you go. Any HTML or script generated for a target lives here (and
on the target's Desktop) — never committed to git. The directory is the one place to
review or replay a run, and the durable home for a device's setup maintenance log.

Export `MACOS_SETUP_TASK_DIR="$(bash scripts/task-init.sh <host>)"` once, and the
scripts route their outputs automatically: raw collection / findings → `raw/`, compare
report / install guide / exclude list → `artifacts/` (the report + guide still land on
the target's Desktop too). Unset, everything falls back to `/tmp` + Desktop as before.

**Remote runs leave the record on the target, so pull it back.** task-init.sh builds
`.history/<host>/<date>-setup/` on the *target* (under its `$HOME`, as the target has no
repo). After each phase, sync it into the orchestrator's repo — that local copy is what
you review and keep:

```bash
bash scripts/sync-history.sh <host> <ssh-target>   # e.g. my-mac my-mac.local
```

## The standard — customize here, nowhere else

| File | Holds |
|---|---|
| `standard/Brewfile.standard` | formulas + casks + mas + taps |
| `standard/Brewfile.optional` | role-dependent extras — ask, never auto-install |
| `standard/blocklist.txt` | explicitly rejected items (removal always per-item confirmed) |
| `standard/node-globals.txt` | Node globals (pnpm -g only) |
| `standard/uv-tools.txt` | Python CLI tools (uv tool) |
| `standard/hotkeys.tsv` | keyboard shortcut baseline — one source for write, verify, report |
| `standard/offline-apps.tsv` | offline installers (bring-your-own / no-cask apps) — staged to Desktop + bilingual guide |
| `scripts/defaults/d*.sh` | system settings / security / power baseline |
| `standard/dock-apps.txt` | Dock pinned apps, left to right (apps not installed are skipped) |
| `standard/agent-ready.tsv` | Agent Device Ready layer (profile `agent-node` only) |

Changing the standard = editing these files. A per-machine opt-out is an order-sheet
rejection — it never edits the standard.

## Human-assist protocol (banner + voice + polling)

1. Scripts hit a human breakpoint → `assist_notify "<what>"` posts a banner
   notification **and** speaks on the **target** machine. Voice is audibility-checked:
   if the output is muted or low, it is raised to a floor (`MACOS_SETUP_VOICE_VOLUME`,
   default 50) for the announcement and restored right after. Everything is logged to
   `/tmp/macos-setup-assist.log`; `MACOS_SETUP_NO_VOICE=1` disables voice.
2. The agent polls the breakpoint condition; each unmet poll calls
   `assist_remind_or_silent` — it self-counts to 3, then goes silent.
3. Breakpoint resolved → re-run the pipeline; idempotency makes re-entry free.

## Local vs remote target

- **Local**: run the scripts directly; `.history/` lands in the repo automatically.
- **Remote (SSH)**: `scripts/remote.sh <host> <ssh-target> <step> [args]` does the whole
  dance — rsync the skill to `/tmp/macos-setup/`, run the step **inside a persistent tmux
  session** (survives disconnects), wait, print the real exit code, pull the run record
  back. `remote.sh <host> <target> --status` peeks at a running step. Manual equivalent:
  `rsync -a <skill-dir>/ <host>:/tmp/macos-setup/`, then execute over SSH in tmux. Voice plays
  on the target — that is where the human is. Interactive confirms need a tty: `ssh -t`.
  The run record builds on the target; pull it back with `scripts/sync-history.sh
  <host> <ssh-target>` after each phase so the orchestrator keeps the reviewable copy.
  If the operator is at a *different* Mac than the target (common: driving the target from
  a laptop), generate the compare report with `MACOS_SETUP_SILENT=1` on the target, then
  `scp` the HTML back and `open` it locally — voice/browser on the target reach no one.

## Iron laws

1. **Zero machine changes before the order sheet is approved.**
2. **Removals are never automatic** — one y/N per item; `brew bundle cleanup --force` is banned.
3. **Every defaults/hotkey write is read back** — unverified writes don't count.
4. **Never uninstall the network transport you arrived on** — adopt only.
5. **`HOMEBREW_BUNDLE_NO_UPGRADE=1`** — upgrading is a separate, deliberate action.
6. **App data outlives app removal** — programs and data are separate decisions.

## Common mistakes

| Mistake | Correction |
|---|---|
| Running the pipeline without precheck | Missing FDA / sign-in makes whole sections fail silently |
| Skipping adopt-pass before bundle | Manually installed apps abort `brew bundle` |
| Reading symbolichotkeys plists by eye | export + plutil JSON, parameter level (pitfalls #6) |
| Deleting rejected items from the Brewfile | The standard stays intact; rejections ride `--exclude-file` |
| Removing app data during cleanup | Data stays by default — removal removes the program |
| Sneaking removals into the pipeline | Removals only via cleanup / order sheet, confirmed each |
| Treating an already-compliant machine as special | Every Mac walks the same three steps |
| Reading an SSH-side "not signed in" as fact | Keychain tools look signed-out over SSH — probe inside the GUI tmux server, else `unknown` |
| Turning on key-only SSH before the key works | `agent-ready` refuses; never hand-edit sshd before `ssh-authorized-key` passes |

## Rationalization check — before executing, ask

- "This machine is special, skip the comparison" → No. Every Mac walks Steps 1–3.
- "The user already decided, removals don't need confirming" → Decision ≠ execution
  consent. Still one y/N each.
- "defaults wrote without an error, so it worked" → Read it back or it didn't happen.
- "This extra tool is great, I'll just install it" → Into `standard/` via a decision,
  never smuggled in.

## References

- [references/agent-ready.md](references/agent-ready.md) — the agent-node profile: lifecycle, layers, verdicts
- [references/pitfalls.md](references/pitfalls.md) — field-tested traps and their countermeasures
- [references/keybindings-standard.md](references/keybindings-standard.md) — shortcut rationale + safe read/write methods
- [templates/setup-report.md](templates/setup-report.md) — convergence checklist skeleton
- [CHANGELOG.md](CHANGELOG.md) — version history (currently v0.2.0)

---

*Powered by [larrykoo711](https://github.com/larrykoo711) — distilled from years of hands-on macOS setup. PRs and field reports welcome.*
