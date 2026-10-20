# Changelog

All notable changes to **macos-setup** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-10-20

### Added
- Pitfalls #48–#53: a removal loop fed on stdin, root-owned App Store apps, a wedged
  syspolicyd hanging a fresh cask CLI, `~/.zshenv` order, proving key-only SSH login, and a
  person's own Chrome holding the agent's debugging port.

### Changed
- Pitfall #47 now says what follows a Claude provider switch by itself and what needs a restart.

## [0.3.0] - 2026-10-20

### Added
- **Optional cc-moss** (`pipeline.sh --with cc-moss`): installs
  [cc-moss](https://github.com/larrykoo711/cc-moss) from its Homebrew tap and runs
  `cc-moss install --yes` (hooks, tmux, starship, shell blocks, menubar app), so Claude Code
  sessions survive crashes and reboots. Opt-in only; `MACOS_SETUP_CCMOSS_SKIP` leaves parts
  the standard already owns alone, and an exclude-file line `cc-moss` skips it.
  `verify.sh` runs `cc-moss doctor` wherever cc-moss is installed. Listed in
  `standard/Brewfile.optional`.

## [0.2.0] - 2026-10-20

Field lessons from setting up blank Macs remotely and turning one into an always-on,
agent-driven node, folded back into the public skill.

### Added
- **Agent-node profile** (`pipeline.sh --profile agent-node`): converges
  `standard/agent-ready.tsv` — key-only SSH, NOPASSWD sudo, non-interactive PATH,
  Tailscale at login, never-sleep / auto-restart / wake-on-LAN, no surprise OS-update
  reboots, FileVault kept on with SSH pre-boot unlock, a tmux server inside the GUI
  session (keychain access for dispatched agents), signed-in claude / gh / git / docker,
  optional 1Password Service Account and OrbStack config. Four-way verdicts
  (`pass` · `fail` · `manual` · `unknown`); `unknown` is never a pass.
  See `references/agent-ready.md`.
- `scripts/agent-bootstrap.sh`: Day-0 key + validated sudoers drop-in, either remotely
  (one password) or as a block to paste on the new Mac.
- `scripts/remote.sh`: run any step on another Mac — rsync, detached run under
  `caffeinate -i`, run lock, wait (an unreachable target is "still running", not "done"),
  real exit code, run-record sync.
- `scripts/sync-user-env.sh`: copy the owner's Claude Code settings / agents / plugins /
  user MCP servers, `CLAUDE.md`, personal `.zshrc` and CC Switch providers to another Mac,
  keeping per-machine choices; opt-outs via `SYNC_SKIP_*` / `SYNC_ZSHRC_MANAGED_TAG`.
- `scripts/claude-channel.sh`: switch another Mac's Claude Code provider to one of its
  CC Switch providers, headless, with read-back.
- Dock standard: `standard/dock-apps.txt` + `scripts/defaults/d03-dock-apps.sh` (via
  `dockutil`) — converges order only, never unpins; verified in `verify.sh`.
- `pipeline.sh --prereqs-only` (Xcode CLT + Homebrew), headless CLT install when sudo is
  passwordless, Node LTS via fnm, Xcode activation + license acceptance.
- Standard: `1password`, `1password-cli`, `dockutil`, `starship`, `zsh-autosuggestions`,
  `zsh-syntax-highlighting`.
- `tests/`: structural guards for the agent-ready standard and a cleanup regression test.
- Pitfalls #31–#47.

### Changed
- `azure-cli` is a cask (Homebrew 7); `tailscale` cask renamed to `tailscale-app`;
  `go` comes straight from Homebrew (no `goenv`).
- App Store sign-in is no longer inferred from an empty `mas list`; the pipeline asks
  the human only when a `mas` entry is actually missing, and every bundle failure names
  the missing entries (pitfalls #10, #40).
- The pnpm globals step sets `PNPM_HOME` itself and never calls `pnpm setup`
  (pitfalls #32).
- `pipeline.sh` holds `caffeinate` for the whole run (pitfalls #34).

### Fixed
- `cleanup.sh` stopped after the first removal whose command read stdin (some cask
  uninstall hooks do): the blocklist is now read on fd 3. Root-owned App Store apps fall
  back to non-interactive sudo.
- `compare.sh` "succeeded" without a report on a blank Mac (`/usr/bin/python3` is a CLT
  stub); it now refuses and points to `--prereqs-only`, and fails if the report is missing.

### Removed
- `gas-mask` (cask disabled upstream), `sesh` (missing tap aborted the bundle).
- A personal app entry in `standard/blocklist.txt`.

## [0.1.0] - 2026-06-30

First public release.

[0.3.1]: https://github.com/larrykoo711/skills/compare/macos-setup-v0.3.0...macos-setup-v0.3.1
[0.3.0]: https://github.com/larrykoo711/skills/compare/macos-setup-v0.2.0...macos-setup-v0.3.0
[0.2.0]: https://github.com/larrykoo711/skills/compare/macos-setup-v0.1.0...macos-setup-v0.2.0
[0.1.0]: https://github.com/larrykoo711/skills/releases/tag/macos-setup-v0.1.0
