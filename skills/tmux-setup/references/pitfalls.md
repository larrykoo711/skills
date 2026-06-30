# tmux-setup — field-tested pitfalls

## 1. A host without your mesh network needs a reachable SSH address

If some machines are on a VPN/mesh (e.g. Tailscale) and others are only on the
LAN, put whatever address actually reaches each host in `devices.conf`'s
`ssh_host` field — a mesh IP for mesh-reachable hosts, a LAN IP/hostname for the
rest. `sync.sh` only ever does `ssh user@host`; it has no built-in knowledge of
any particular network topology, so the address you put in the inventory is the
address it uses.

## 2. macOS `gem install` hits EACCES + the gem bin dir isn't on PATH

macOS 15+ restricts the system Ruby, so `gem install tmuxinator` fails with
EACCES. Fix by using Homebrew's Ruby:

```bash
brew install ruby
export PATH="$(brew --prefix ruby)/bin:$PATH"
gem install tmuxinator --no-document
```

The gem-installed binaries land in Homebrew Ruby's gem dir, which must also be on
PATH. `sync.sh` writes a `BREW_GEM_PATH_INIT` block into `~/.zprofile` that
resolves both dirs dynamically:

```bash
_brew_ruby_bin="$(brew --prefix ruby)/bin"
_brew_gem_bin="$(${_brew_ruby_bin}/gem env gemdir)/bin"
export PATH="${_brew_gem_bin}:${_brew_ruby_bin}:$PATH"
```

Resolving the gem dir at runtime (instead of hard-coding a version like
`gems/4.0.0/bin`) means a Ruby upgrade doesn't silently break `tmuxinator`.

## 3. Ubuntu: use the system `ruby-full` package, no rbenv needed

`sudo apt install ruby-full` is enough. `sudo gem install tmuxinator` installs it
system-wide for all users. This is why the Ubuntu path needs passwordless sudo
(see SKILL.md) — without it `sync.sh` stops and tells you how to grant it.

## 4. `t clean` on a Linux server keeps only the shell window

The Linux template ships a single `shell` window. `_t_clean_session` protects the
window names `shell` and `claude`; on a host where `claude` doesn't exist it's
simply skipped — no error, correct behavior.

## 5. fzf from apt on older Ubuntu can be too old

Ubuntu 20.04's apt fzf is 0.20.x and lacks flags like `--border`. Install fzf
from its GitHub release script, or `snap install fzf` where snap is available.

## 6. SSH key-based login must already work

`sync.sh` connects non-interactively (`BatchMode=yes`); it does not set up keys.
Make sure `ssh user@host` succeeds without a password for every host in
`devices.conf` before running. Point `TMUX_SETUP_SSH_KEY` at your key if it isn't
the default `~/.ssh/id_ed25519`.

## 7. bash `local` only works inside a function

The bash `local` keyword is only valid in a function body. `bash -n` won't flag a
top-level `local`, but it fails at runtime — keep every `local` declaration inside
a function.
