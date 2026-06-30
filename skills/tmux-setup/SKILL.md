---
name: tmux-setup
version: 0.2.0
description: Deploys a consistent terminal standard — tmux config, an interactive `t` session manager, and tmuxinator project templates — across one or many machines over SSH, idempotently and with per-file diff confirmation. Handles macOS (Homebrew), Ubuntu (apt), and OpenWrt (opkg) differences. Use when setting up tmux on a new machine, syncing a tmux/tmuxinator/`t` CLI config to remote hosts, standardizing terminals across several machines, or onboarding a server's shell environment (tmux setup, 终端标准, tmux 配置同步, 多机终端). Not for one-off `tmux` installs you'd do by hand, or for managing tmux at runtime.
---

# tmux-setup

**Declare one terminal standard. Push it to every machine, the same way.**

This skill installs and syncs a single terminal environment — a tmux config, an
interactive `t` session/window/folder picker (fzf-driven), and tmuxinator project
templates — onto any number of machines listed in an inventory file. One script
(`scripts/sync.sh`) does first-time install and later updates alike: it detects
what's already there, shows a diff before touching anything, and asks per host.

Three guarantees:

1. **Diff before write** — every file is compared against what's on the host; you
   see the diff and confirm before it's overwritten.
2. **Idempotent** — re-run any time. Already-satisfied steps are skipped, so a
   re-run only does what's missing.
3. **One host at a time** — multi-host runs confirm each machine and pause between
   them. Nothing is deployed silently in bulk.

## When to use

- Setting up tmux + `t` + tmuxinator on a fresh machine (local or remote).
- Syncing an edited config out to the machines that already have it.
- Standardizing the terminal across several hosts of mixed platforms.
- Onboarding a server's shell environment in one pass.

**Not for**: a one-off `tmux`/`fzf` install you'd just do by hand, or changing a
live tmux session at runtime.

## Setup: the inventory

The list of machines lives in `devices.conf` (gitignored), not in any script.
Start from the template:

```bash
cp devices.example.conf devices.conf
# edit devices.conf — one machine per line:
#   host_id | platform | ssh_user | ssh_host | display_name
```

`platform` is one of `macos` / `ubuntu` / `openwrt` / `local`. See
[references/device-matrix.md](references/device-matrix.md) for what each platform
installs and which `t.zsh` / tmuxinator variant it gets.

**Prerequisite**: key-based SSH login must already work for every host
(`ssh user@host` connects without a password). `sync.sh` connects non-interactively
and does not set up keys. Point `TMUX_SETUP_SSH_KEY` at your key if it isn't the
default `~/.ssh/id_ed25519`.

## Quick start

```bash
cd scripts
./sync.sh                 # interactive menu — pick hosts from the inventory
./sync.sh workstation     # one host by id
./sync.sh web1 web2       # several hosts
./sync.sh --all           # every host in devices.conf
./sync.sh --dry-run       # show diffs only, change nothing
```

`sync.sh` is the single entry point for both first-time install and later syncs.
For each selected host it: tests SSH → detects current state → installs missing
deps for that platform → pushes `~/.tmux.conf` and `~/.zsh/t.zsh` (diff-confirmed)
→ wires up the shell rc files → verifies → reports.

## Interaction protocol

Before deploying, always:

1. **Confirm the targets** — show the hosts from `devices.conf` and let the user
   pick (one or several). Never assume "all".
2. **Show the plan** — which deps install, which files get pushed, what gets
   overwritten.
3. **Diff-confirm** — if a config already exists on the host, show the diff and
   ask before overwriting. `sync.sh` does this per file.
4. **One host at a time** — on multi-host runs, report each result and ask before
   moving to the next.

Never deploy to every host silently. `--force` (skip confirmations) exists for
CI/cron only — don't use it interactively.

## Platform notes

- **macOS** — Homebrew installs tmux/fzf/zoxide and a Homebrew Ruby for
  `tmuxinator` (the system Ruby fails with EACCES — see pitfalls #2). PATH for the
  gem bins is wired into `~/.zprofile` dynamically, so a Ruby upgrade doesn't break
  it. Works on Apple Silicon and Intel (brew prefix auto-detected).
- **Ubuntu** — apt installs tmux/fzf/ruby-full; `tmuxinator` via `gem install`.
  Needs passwordless sudo — if it's missing, `sync.sh` stops and prints exactly how
  to grant it, then you re-run.
- **OpenWrt** — minimal: tmux + a lightweight `t()` (no fzf/sesh/tmuxinator), and a
  trimmed tmux.conf (macOS-only lines stripped).

## The `t` CLI

`templates/t.zsh` is an fzf-driven picker over tmux **sessions**, **windows**, and
**folders** (zoxide), with create/attach/stop/remove and a `t clean` that prunes
scratch windows. Its fzf helper scripts are written to a per-user private dir
(`${XDG_RUNTIME_DIR:-$HOME/.cache}/t`), never a world-writable `/tmp` path. Run
`t --help` on a deployed host for the full key map.

## tmuxinator templates

`templates/tmuxinator/` holds starter project templates. The macOS one carries a
`claude` window (a Claude Code session) plus a `shell`; the Linux one is `shell`
only. Copy one to `~/.config/tmuxinator/<project>.yml` and edit `name`/`root`.
The `claude` window is a convention — rename or drop it freely.

## Common mistakes

| Goal | Wrong | Right |
|------|-------|-------|
| Deploy to several hosts | Run all silently | Confirm each, one at a time |
| A host not on your mesh | Put a mesh IP it can't reach in `ssh_host` | Put a reachable LAN IP/hostname (pitfalls #1) |
| Overwrite an existing `.tmux.conf` | Overwrite without showing a diff | Diff first, confirm |
| Install `tmuxinator` on macOS | System Ruby `gem install` → EACCES | Homebrew Ruby (pitfalls #2) |
| Pin the gem PATH | Hard-code `gems/4.0.0/bin` in `.zshrc` | Dynamic `BREW_GEM_PATH_INIT` in `.zprofile` |
| OpenWrt gets the full `t.zsh` | fzf/sesh missing → source errors | The minimal `t()` variant (automatic) |
| tmuxinator `root:` | A path only one machine has | A path that exists everywhere (e.g. `~/Documents`) |

## Rationalization check

- Tempted to skip the diff and just overwrite? → No. Show the diff, confirm.
- Tempted to deploy the whole inventory in one silent command? → No. One host at a
  time, confirmed.
- Pushing the macOS template (with its `claude` window) to a Linux box? → No. Match
  the template to the platform.

## References

- [references/device-matrix.md](references/device-matrix.md) — platform → install
  path / `t.zsh` variant / tmuxinator template mapping, and SSH-key resolution.
- [references/pitfalls.md](references/pitfalls.md) — seven field-tested traps
  (macOS Ruby EACCES, old apt fzf, mesh-vs-LAN addressing, and more).
- [CHANGELOG.md](CHANGELOG.md) — version history (currently v0.2.0).

---

*Powered by [larrykoo711](https://github.com/larrykoo711) — a terminal standard refined across many machines. PRs and field reports welcome.*
