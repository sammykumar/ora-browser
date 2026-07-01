# Ora → Evo Complete Rename (Hard Fork)

**Date:** 2026-06-30
**Status:** Approved design

## Goal

Remove every Ora reference in the codebase except the GPL-3.0-mandated attribution
floor. This reverses the prior "keep internal names `Ora*` to ease upstream rebasing"
policy: the project now treats Evo as a **standalone hard fork** and stops tracking
`the-ora/browser`. With no future rebases, the rebase-friction argument that kept
`Ora*` identifiers no longer applies, and the machinery that existed only to serve
rebasing becomes dead weight to delete.

## Decisions settled during brainstorming

| Decision | Choice | Consequence |
|---|---|---|
| Rename scope | Everything, including internal Swift types | Full de-Ora'ing; no symbol left as `Ora*` |
| Upstream tracking | Abandon — hard fork | Lose automatic upstream bugfixes/features unless cherry-picked manually |
| Rebase machinery | Delete all of it | FORK_PATCHES, upstream release scripts, Sparkle artifacts removed |
| In-app logo art | Reuse existing Evo app-icon art (`EvoLogo.svg`) | No Ora glyph remains; nothing blocks on new artwork |

## Hard constraint (non-negotiable)

Ora is licensed **GPL-3.0**. Even as a hard fork:

- `LICENSE` must retain Ora's copyright and the GPL-3.0 text — untouched.
- The project must note it is **derived from Ora Browser (GPL-3.0)** with upstream
  copyright retained.

This is the attribution *floor*. Everything above it (how prominent the fork framing
is, whether docs link upstream) is trimmed, but the floor stays.

## Verified findings that shape the work

- **No data-orphaning risk.** `oraDatabase`, `createOraContainer`, `oraDefault`,
  `oraShortcut`, `oraShortcutHelp` are pure Swift identifiers. None embeds "ora" in an
  on-disk SwiftData store name, `UserDefaults` suite, or App Group. Renaming them is
  purely cosmetic — no local data is orphaned.
- **Entitlement values already clean.** The `mach-lookup` global-name array derives
  from `$(PRODUCT_BUNDLE_IDENTIFIER)` (already `com.skproductions.evobrowser`) via the
  `-spks`/`-spki` Sparkle XPC suffixes. Only the entitlement *filenames* carry "ora".
- **App-icon art is already Evo.** `OraIcon.icon` / `OraIconDev.icon` bundles contain
  `EvoLogo.svg` and `EvoAccents.svg`. Only the in-app imagesets (home-screen logo,
  window profile icon) still hold Ora glyph pixels.
- **JavaScript already de-Ora'd.** WebScripts use `__evo*` globals and
  `data-evo-password-field-id`. `mark.js` is vendored Mark.js (third-party) — leave it.
- **`Ora`-capitalized whole-word replacement is safe.** No other identifier in
  `evo/`/`evoTests/` contains `Ora` as a substring (verified — no `aurora`, `decorator`,
  etc. in our own symbols). Lowercase `ora` is NOT safe to blanket-replace (`storage`,
  `decorator`, etc.), so lowercase identifiers are handled by exact name.

## Scope of changes

### 1. Swift symbols (~126 occurrences across 8 files)

Rename by **exact identifier**, not blanket text replace.

**Types → `Evo*`:**
`OraApp`, `OraRoot`, `OraCommands`, `OraBrowserScripts`, `OraButton`,
`OraButtonVariant`, `OraButtonSize`, `OraInput`, `OraInputVariant`, `OraIcons`,
`OraIconType`, `OraIconSize`, `OraWindowDragGesture`, `OraShortcutHelpModifier`,
`OraKeyboardShortcutModifier`. Test class `OraTests → EvoTests`.

**Lowercase identifiers (exact-name replace):**
`oraShortcut → evoShortcut`, `oraShortcutHelp → evoShortcutHelp`,
`oraDefault → evoDefault`, `oraDatabase → evoDatabase`,
`createOraContainer → createEvoContainer`.

**File renames (`git mv` to preserve history):**
- `evo/App/OraApp.swift → EvoApp.swift`
- `evo/App/OraRoot.swift → EvoRoot.swift`
- `evo/App/OraCommands.swift → EvoCommands.swift`
- `evo/Core/BrowserEngine/Scripts/OraBrowserScripts.swift → EvoBrowserScripts.swift`
- `evo/Shared/Components/Buttons/OraButton.swift → EvoButton.swift`
- `evo/Shared/Components/Icons/OraIcon.swift → EvoIcon.swift`
- `evo/Shared/Components/Inputs/OraInput.swift → EvoInput.swift`
- `evoTests/oraTests.swift → evoTests.swift`

### 2. Assets

**Catalog directory renames (`git mv`), inner file renames, and `Contents.json`
`filename` updates:**

| From | To |
|---|---|
| `OraIcon.appiconset` (`ora-white-macos-icon.png`) | `EvoIcon.appiconset` (`evo-white-macos-icon.png`) |
| `OraColorLogo.imageset` (`ora-color-logo.png`, `ora-color-logo 1.png`) | `EvoColorLogo.imageset` (`evo-color-logo.png`, `evo-color-logo 1.png`) |
| `ora-logo-plain.imageset` (`Ora Browser Logo.svg`) | `evo-logo-plain.imageset` (`evo-logo-plain.svg`) |
| `ora-logo-outline.imageset` (`Ora Browser Logo (1).svg`) | `evo-logo-outline.imageset` (`evo-logo-outline.svg`) |
| `appearance-system.imageset` (`Ora Browser System.png`) | `appearance-system.imageset` (`evo-appearance-system.png`) |
| `OraIcon.icon` bundle | `EvoIcon.icon` |
| `OraIconDev.icon` bundle | `EvoIconDev.icon` |

**Art swap:** Copy/point `evo-logo-plain` and `evo-color-logo` slots at the existing
`EvoLogo.svg` art (from the `.icon` bundle) so the home-screen logo and window profile
icon display Evo, not the Ora glyph. The `appearance-system` image is a generic
light/dark appearance preview, not a logo — rename the file only, keep the pixels.

**Swift string reference updates:**
- `evo/App/OraRoot.swift:161` — `Image("OraColorLogo") → Image("EvoColorLogo")`
- `evo/Features/Browser/Views/HomeView.swift:35` — `Image("ora-logo-plain") → Image("evo-logo-plain")`
- Any other `Image("...")` referencing a renamed asset.

### 3. Build config (`project.yml`) + entitlements

- `git mv evo/Info/ora.entitlements → evo.entitlements`
- `git mv evo/Info/ora-debug.entitlements → evo-debug.entitlements`
- `project.yml` updates:
  - `CODE_SIGN_ENTITLEMENTS` paths (Debug + Release) → `evo.entitlements`
    (or `evo-debug.entitlements` where the debug one is referenced).
  - `.icon` bundle input/output paths in the "Copy Icon Bundle" build phase →
    `EvoIcon.icon` / `EvoIconDev.icon`.
  - `ASSETCATALOG_COMPILER_APPICON_NAME: OraIconDev → EvoIconDev` (Debug),
    `OraIcon → EvoIcon` (Release).
- Re-run `xcodegen` after file/config renames (the `.xcodeproj` is generated,
  gitignored).

### 4. Deletions (dead rebase machinery)

Delete:
- `FORK_PATCHES.md`
- `scripts/build.sh`, `scripts/release.sh`, `scripts/publish.sh`, `scripts/_common.sh`,
  `scripts/generate-changelog.py`, `scripts/prompts/`
- `appcast.xml`, `ora_public_key.pem`

**Keep:** `scripts/xcbuild-debug.sh` (the active local-dev build path).

### 5. Docs

- **Rewrite `CLAUDE.md`:** strip all "internal names stay `Ora*`", "re-apply after
  rebase", and `FORK_PATCHES.md` guidance. Remove warnings about the deleted upstream
  scripts. Describe Evo as a standalone macOS browser project. Retain the GPL/derived-
  from-Ora attribution note. Keep the still-accurate architecture/commands/style
  sections.
- **Trim `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `ROADMAP.md`** to the GPL
  attribution floor: a one-line "derived from Ora Browser (GPL-3.0), upstream copyright
  retained" note. Drop "tracks upstream closely" / "personal fork of" framing where it
  is not required for attribution.
- **`LICENSE`:** untouched.

## Execution approach

**Ordered categories with build checkpoints** (chosen over a single scripted global
find-replace and over Xcode semantic rename).

Order:
1. Swift symbol renames (types, then lowercase idents) + file `git mv`s.
2. Asset renames + art swap + string-ref updates.
3. Entitlement file renames + `project.yml` updates + `xcodegen`.
4. Deletions.
5. Doc rewrites.

Build with `./scripts/xcbuild-debug.sh` after each of categories 1–3 so any breakage is
localized to the category that caused it. `Ora`-capitalized replaces use whole-word
matching; lowercase idents use the exact-name list above.

### Rejected alternatives

- **Single scripted global find-replace** — fast but one substring collision (e.g.
  matching `ora` inside `storage`) breaks the build silently and is hard to localize.
- **Xcode semantic rename** — correct for symbols, but cannot touch asset catalogs,
  file names, or string literals, and is not scriptable.

## Verification / success criteria

1. Clean Debug build via `./scripts/xcbuild-debug.sh`.
2. App launches; home-screen logo and window profile icon show Evo art (no Ora glyph).
3. `grep -riE '\bora' evo evoTests project.yml` returns **only**:
   - Vendored `mark.js` (Mark.js library) hits.
   - The GPL "derived from Ora Browser" attribution line(s).
4. No `Ora*` Swift symbol, asset name, or entitlement filename remains.
5. Deleted files are gone; `scripts/xcbuild-debug.sh` still present and working.
