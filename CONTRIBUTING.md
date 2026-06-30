# Contributing

Thanks for considering a contribution. This repo holds a small set of
high-standard agent skills; every skill must clear the same bar before it ships.

## Language

This is an international open-source project. **All developer-facing content is
English** — code, comments, documentation, commit messages, issues, and pull
requests. The only exception is **end-user-facing UI strings**, which may be
bilingual (e.g. a skill that renders a report for a human can localize that
report); these are a product feature, not project documentation.

## The bar every skill must clear

- **A clear `SKILL.md`** with valid frontmatter: a `name` (kebab-case, no
  `claude`/`anthropic`) and a `description` that states what it does and when to
  use it (trigger conditions, no `MUST`/`ALWAYS` filler). Keep `SKILL.md` under
  500 lines; push detail into `references/`.
- **No leaking** of secrets, credentials, private hostnames/IPs, or local
  absolute paths. Use placeholders and environment variables.
- **Real-tool recipes** — scripts must run standalone, be parameterized with
  env-var fallbacks, and never hard-code a project path.
- **Fail fast, fail clear** — surface a helpful message, not a raw traceback.
- **Self-contained** — each skill lives under `skills/<name>/` and declares
  itself in [`skills.sh.json`](skills.sh.json).

## Workflow

1. Branch from `main` (e.g. `feat/<skill>` or `fix/<skill>-<topic>`).
2. Make your change; keep commits focused and messages in
   [Conventional Commits](https://www.conventionalcommits.org/) form.
3. Open a pull request against `main` describing what changed and why.
4. A maintainer reviews against the bar above before merge.

## License

By contributing, you agree your contributions are licensed under the
[MIT License](LICENSE).
