# macos-setup convergence checklist — {host} · {date}

> Produced after a pipeline run. Findings source: /tmp/macos-setup-findings.txt
> Every line is a read-back fact (✅ verified / ❌ drifted), not an assumption.

## Software baseline (brew bundle · pnpm -g · uv tools)

{paste the install/bundle findings: each line ✅/❌ + command}

## Settings · shortcuts · security · power (verify.sh read-back)

{paste the baseline findings: each line ✅/❌ + actual value}

## Removals executed (one-by-one confirmations)

{list each removal: name + command + result; "none" if no removals this run}

## Remaining manual breakpoints

- [ ] App Store sign-in (then re-run the pipeline — re-entry is free)
- [ ] rustup-init (Rust toolchain bootstrap)
- [ ] FileVault / SIP (if findings say off)
- [ ] Local packages not yet installed (bring-your-own / no-cask apps)
- [ ] {any finding that needs a human}

## Re-run (idempotent)

```bash
bash scripts/pipeline.sh --exclude-file /tmp/macos-setup-exclude.txt
bash scripts/verify.sh        # audit any time, read-only
```
