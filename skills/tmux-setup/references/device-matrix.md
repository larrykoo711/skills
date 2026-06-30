# Platform → template mapping

Each machine in your `devices.conf` declares a `platform`. That platform decides
which dependencies get installed, which `t.zsh` variant is pushed, and which
tmuxinator template fits.

| platform | install path | `t.zsh` variant | tmuxinator template | notes |
|----------|-------------|-----------------|---------------------|-------|
| `macos`   | Homebrew (tmux, fzf, zoxide, brew-ruby + tmuxinator) | full (fzf picker) | `macos-server.yml.tpl` | full feature set |
| `ubuntu`  | apt (tmux, fzf, ruby-full) + `gem install tmuxinator`; needs passwordless sudo | full (fzf picker) | `linux-server.yml.tpl` | apt fzf can be old — see pitfalls #5 |
| `openwrt` | opkg (tmux + openssh-sftp-server) | minimal (no fzf/sesh) | — | lightweight `t()` only |
| `local`   | same as the host's OS, operated directly (no SSH) | full | matches OS | for the machine you run `sync.sh` from |

## SSH key

`sync.sh` connects with a single key, resolved as:

```
$TMUX_SETUP_SSH_KEY   →   ~/.ssh/id_ed25519   (default)
```

Set `TMUX_SETUP_SSH_KEY` if your key lives elsewhere or has a different name.
Make sure key-based SSH login already works for each host in `devices.conf`
(`ssh user@host` should connect without a password prompt) before running
`sync.sh`.

## tmuxinator templates

The templates carry a `claude` window (a [Claude Code](https://claude.com/claude-code)
session) on the macOS server template and a plain `shell` window on the Linux one.
Drop the `claude` window or rename it freely — it's just a convention, not a
requirement.
