# Keyboard shortcut baseline — rationale & methods

**Source of truth: `standard/hotkeys.tsv`** (id / enabled / description).
`d06-keybindings.sh` writes it, `verify.sh` · `collect.sh` · `compare.sh` read it.
Change the standard there; this file explains the reasoning and the safe methods.

## The decisions behind the baseline

| Function | symbolichotkey id | Standard | Why |
|---|---|---|---|
| Launcher | — (not a symbolichotkey) | **Raycast, double-tap ⌘** | Set inside Raycast on first launch; keeps ⌘Space-class bindings free |
| Spotlight | 64 / 65 | off | The launcher owns search |
| Legacy input switch | 60 (⌃Space) | off | Avoid conflicts with editor keymaps |
| Input source switch | 61 | **on = Globe key** `[65535, 105, 8388608]` | One dedicated key, zero collisions; d06 writes the full parameters |
| System screenshots | 28–31 / 184 | off | Delegated to a dedicated screenshot app (local package) |
| Screen recording options | 239–247 | untouched | Owned by the screenshot app |
| Mission Control / Desktop | 32–36 | off | Unused with a launcher-centric flow |
| Switch Spaces | 79–82 | **80/82 on · 79/81 off** | Right-switch kept, left via gesture |
| Keyboard focus navigation | 7–13 / 57 | off | Unused |
| Cycle windows ⌘` | 27 | off | Unused |
| Accessibility zoom | 15–26 | **15/17/19/23 on, rest off** | Zoom toggle/in/out/smoothing only |
| Zoom shortcuts | 55/56 | on | Quick zoom without the accessibility panel |
| Dock auto-hide toggle | 52 | off | Dock state is fixed by the baseline (d02) |
| Dictation | 175 | off | Unused; avoids accidental double-press triggers |
| Window tiling | 248–251 | on | Native tiling stays available |
| Display brightness / DND / Launchpad | 53/54/164/160–163 | untouched | System defaults are fine |
| App menu re-binds | NSUserKeyEquivalents | empty | No per-app key overrides |
| Low-level remapping | (Karabiner etc.) | not installed | Keep the key event chain clean |

## Input method engine

The standard engine is **Sogou Pinyin** — no cask exists, so it is a manual
install: official pkg from https://pinyin.sogou.com/mac/, then System Settings →
Keyboard → Input Sources → add it (manual breakpoint; the pipeline reminds by voice).

## Read / write methods (always do it this way)

```bash
# READ — parameter level. Never interpret the raw plist by eye:
# modifier masks are extremely easy to misread (see pitfalls #6).
defaults export com.apple.symbolichotkeys - | plutil -convert json -o - -

# WRITE — through cfprefsd; direct plist edits get overwritten by the cache.
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
  '<dict><key>enabled</key><false/></dict>'

# APPLY — no logout needed.
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
```
