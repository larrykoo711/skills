# Changelog

All notable changes to **tmux-setup** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-06-30

First public release. Generalized from a personal multi-machine setup into a
publishable, standalone skill.

### Added
- External machine inventory: hosts now live in `devices.conf` (gitignored),
  seeded from `devices.example.conf`, instead of being hard-coded in the script.
- `version` field in `SKILL.md` frontmatter and this `CHANGELOG.md`.

### Changed
- `tmux.conf`: `detach-on-destroy` now defaults to `on` (tmux's own default).
  With `off`, closing the active session switched the client to another live
  session — so multiple windows attached to different sessions could collide on
  the same one. `on` detaches to the shell instead. (Reported behavior.)
- `t.zsh` SSH key resolution is parameterized via `TMUX_SETUP_SSH_KEY`
  (default `~/.ssh/id_ed25519`); no key name is hard-coded.
- Homebrew prefix is auto-detected, so macOS install works on both Apple Silicon
  (`/opt/homebrew`) and Intel (`/usr/local`).
- All developer-facing surfaces (comments, docs, script output) are now English;
  the `SKILL.md` description keeps bilingual trigger keywords. End-user-facing
  bilingual UI is unaffected.

### Fixed
- **Security**: `t.zsh` wrote its fzf helper scripts to predictable, world-writable
  `/tmp` paths and `chmod +x`'d them, opening a symlink/arbitrary-code-execution
  vector on shared hosts. Helpers now go to a per-user private directory
  (`${XDG_RUNTIME_DIR:-$HOME/.cache}/t`, mode 700).
- `t --version` rendered an empty author (trailing `· `) because the `# author:`
  header line was missing. Restored.

### Removed
- The legacy `deploy.sh` + `scripts/lib/` deploy path, which duplicated `sync.sh`
  and contradicted its own documented EACCES workaround. `sync.sh` is now the
  single entry point for first-time install and later syncs.
- All personal data (real hostnames, mesh/LAN IPs, SSH usernames, key names) and
  the cross-skill dependency on a private network-topology skill.

[0.2.0]: https://github.com/larrykoo711/skills/releases/tag/tmux-setup-v0.2.0
