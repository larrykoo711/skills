# Agent Device Ready — the agent-node profile

A Mac is **agent-ready** when an agent can reach it, run long work on it, and trust
what it reports — with nobody sitting in front of it. The items live in
`standard/agent-ready.tsv`; `scripts/agent-ready.sh` checks and converges them.

## Lifecycle of a new agent-node

| Step | Where | Who | What |
|---|---|---|---|
| 0 | the new Mac | human, once | Sharing → Remote Login ON + "full disk access for remote users"; paste the block from `agent-bootstrap.sh --pubkey <key.pub>` |
| 1 | operator Mac | agent | `remote.sh <host> <target> precheck` |
| 2 | operator Mac | agent | `remote.sh <host> <target> compare` → open the synced HTML locally, user approves |
| 3 | operator Mac | agent | `remote.sh <host> <target> pipeline --profile agent-node [--exclude-file …]` |
| 4 | the new Mac | human, once | the `manual` items `agent-ready --check` still lists (sign-ins, console login) |
| 5 | operator Mac | agent | `remote.sh <host> <target> agent-ready --apply` until 0 fail · 0 manual · 0 unknown |

After step 0 no one needs to be at the machine again except for sign-ins that
require a browser or a GUI click (step 4). The human checklist for step 4, in one visit:

- Tailscale.app: open once, allow the VPN configuration, sign in (then: fixed IP + disable key expiry in the admin console)
- OrbStack.app: open once, approve the helper (install its cask inside the GUI tmux — pitfalls #39)
- Claude Code: `claude auth login` inside the GUI tmux, approve in the browser
- 1Password app: sign in; for agents create a Service Account limited to the agent vaults and store its
  token with `read -rs … | ssh target 'umask 077; cat > ~/.config/agent-secrets/op-sa.token'`
  (another path: set `AGENT_OP_TOKEN_FILE`; no 1Password at all: exclude `agent:op-service-account`)
- Owner accounts with passkeys (GitHub): sign in once by hand in whatever browser the agents use
- `cd <workspace> && claude` once per workspace root to accept the folder-trust prompt

## Why each layer exists

**reach** — the agent has to get in and find its tools.
- Key-only SSH is applied *after* `authorized_keys` passes; the apply refuses otherwise
  (locking the only door is the one failure this layer must never cause).
- `noninteractive-path` simulates exactly what sshd gives `ssh host cmd`: minimal PATH,
  zsh reading only `.zshenv`. A tool that is installed but invisible there reads as
  "not installed" to every agent — the fix belongs in `~/.zshenv`, not in this layer.
- `remote-fda` can only be probed from an SSH session; elsewhere it is `unknown`.

**always-on** — the machine has to still be there tomorrow.
- System + disk sleep 0, auto-restart after power loss, wake-on-LAN.
- macOS OS updates are not auto-installed (a 3 a.m. reboot kills every tmux session);
  security responses stay automatic.
- **FileVault stays on.** macOS 26+ on Apple Silicon unlocks FileVault over SSH at
  pre-boot when Remote Login was on before the reboot: ssh in, give the password,
  the session closes, reconnect. The pre-boot host key differs from the normal one —
  expect one host-key warning. Planned reboots: `sudo fdesetup authrestart` skips it.
  Turning FileVault off just to get auto-login is not worth a stolen-disk exposure.
- **The tmux server lives in the GUI session.** Processes started from SSH can't read
  the login keychain, so `claude`, `gh` and anything else that stores tokens there
  look signed-out over SSH. A LaunchAgent (`com.macos-setup.agent-tmux`) starts the
  tmux server inside the console session; every `tmux new-session` from SSH then
  joins that server and inherits keychain access. It requires a console login
  (`gui-session`) — after a reboot, log in once (Screen Sharing works).
  If a tmux server was already started from SSH before the agent, kill it
  (`tmux kill-server`) and re-apply, or new sessions join the wrong one. `tmux-gui-server`
  cannot tell the two apart (the default socket is shared on purpose so every tmux client
  and dispatcher sees the same sessions) — the keychain probes (`claude-auth`, `gh-auth`) are
  what catch it: they fail inside a server that is not in the GUI session.

**toolchain** — signed in, identified, able to run containers.
- 1Password for agents is a **Service Account** token in a 600 file (`AGENT_OP_TOKEN_FILE`,
  default `~/.config/agent-secrets/op-sa.token`), never the desktop app — it prompts per terminal
  session and is invisible from launchd-started process trees.
- OrbStack: start at login, k8s off (enable on demand). Set `AGENT_ORBSTACK_SUBNET4`
  (e.g. `172.29.0.0/23`) to pin the same container subnet on every node, away from your LANs;
  unset leaves OrbStack's default. Install GUI casks like OrbStack *inside* the GUI tmux
  server (pitfalls #39).
- The sign-ins are `manual`: each needs a browser once. Keychain-backed probes run *inside* the
  GUI tmux server, so a pass means "works for a dispatched agent", not just "works in some shell".
- An agent browser (a dedicated Chrome profile with a loopback debugging port) is deliberately
  not part of this layer — see pitfalls #42 for why it should be real Chrome with its own
  `--user-data-dir` rather than Chrome for Testing.

## Verdicts

`pass` · `fail` · `manual` (only a human can fix) · `unknown` (could not be probed from
here). Exit 0 only when everything passes — `unknown` is never a pass.

## Opt-outs

Order-sheet rejections apply here too: put `agent:<id>` in the exclude file.
