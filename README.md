# larrykoo711/skills

High-standard, open-source [agent skills](https://skills.sh) distilled from
years of hands-on infrastructure work — one monorepo so every skill ships with
the same quality bar (clear safety contracts, real-tool recipes, no leaking of
secrets or local paths).

Skills work with Claude Code, Cursor, Copilot, and 70+ other agents via
[skills.sh](https://skills.sh).

## Install

Install everything:

```
npx skills add larrykoo711/skills
```

Or a single skill:

```
npx skills add larrykoo711/skills@macos-setup
npx skills add larrykoo711/skills@tmux-setup
```

## Skills

| Skill | Group | Description |
|-------|-------|-------------|
| [macos-setup](skills/macos-setup/SKILL.md) | macOS | Standard-driven macOS setup: declare your Mac once in a `standard/`, then converge any machine to it — read-only audit, interactive decision report, idempotent pipeline with explicit human checkpoints, and every defaults/hotkey write read back to confirm it took. Optional `agent-node` profile makes a Mac Agent Device Ready (always-on, headless, agent-driven), driven remotely from another Mac. |
| [tmux-setup](skills/tmux-setup/SKILL.md) | Terminal | Deploy a consistent terminal standard — tmux config, an interactive `t` session manager, and tmuxinator templates — to one or many machines over SSH. Idempotent, diff-confirmed, one host at a time; handles macOS / Ubuntu / OpenWrt. |

## Why a monorepo

One repo, one quality bar. Each skill is self-contained under `skills/<name>/`
(a `SKILL.md` plus optional `references/`, `scripts/`, `standard/`, `templates/`),
declared in [`skills.sh.json`](skills.sh.json). Publishing many skills from a
single high-standard repo is easier to govern, version, and review than a repo
per skill — and consumers can still install any skill individually with
`larrykoo711/skills@<name>`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the bar every skill must clear.

## License

MIT © [larrykoo711](https://github.com/larrykoo711)
