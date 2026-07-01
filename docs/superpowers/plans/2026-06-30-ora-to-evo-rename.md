# Ora → Evo Complete Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove every Ora reference in the codebase (Swift symbols, assets, entitlement filenames, docs) except the GPL-3.0 attribution floor, and delete the dead upstream-rebase machinery.

**Architecture:** Ordered mechanical rename in build-checkpointed categories: (1) Swift symbols + file moves as one atomic pass, (2) in-catalog image assets + art swap, (3) app-icon assets + entitlements + `project.yml`, (4) deletions, (5) doc rewrites. Each task ends with a clean Debug build and a commit so any breakage is localized. Symbol replacement uses `perl -pi` (BSD `sed` on macOS has no `\b`) against an exact identifier list — never a blanket `Ora`/`ora` text sweep.

**Tech Stack:** Swift / SwiftUI / WKWebView, XcodeGen (`project.yml` → generated `Evo.xcodeproj`), Xcode asset catalogs, `perl`/`git mv` for the rename mechanics.

## Global Constraints

- **GPL-3.0 attribution floor (non-negotiable):** `LICENSE` stays untouched; the project must retain a note that it is derived from Ora Browser (GPL-3.0) with upstream copyright retained. This is the ONLY place "Ora" may remain in prose.
- **No data-orphaning:** `oraDatabase`/`createOraContainer`/`oraDefault`/`oraShortcut` are pure Swift identifiers — renaming them changes no on-disk store name, `UserDefaults` suite, or App Group. Verified. No migration needed.
- **Rename by exact identifier only.** Capitalized `Ora*` is whole-word-safe (no other symbol contains `Ora` as a substring — verified). Lowercase `ora` is NOT safe to blanket-replace (`storage`, `decorator`, …) — use the exact lowercase list in Task 1.
- **`Evo.xcodeproj` is generated and gitignored.** Run `xcodegen` after any file move or `project.yml` edit, before building.
- **Build gate:** `./scripts/xcbuild-debug.sh` must exit 0 at the end of Tasks 1–4. Do not proceed past a red build.
- **Leave vendored code alone:** `evo/Resources/WebScripts/mark.js` (Mark.js) and `evo/Shared/Layout/SplitView` (vendored upstream) are not renamed.
- **Preserve git history:** use `git mv` for every file/directory rename.

---

### Task 1: Rename Swift symbols and source files

**Files (modify — symbol occurrences, ~126 across 27 files):**
All `*.swift` under `evo/` and `evoTests/` that reference the identifiers below.

**Files (rename via `git mv`):**
- `evo/App/OraApp.swift` → `evo/App/EvoApp.swift`
- `evo/App/OraRoot.swift` → `evo/App/EvoRoot.swift`
- `evo/App/OraCommands.swift` → `evo/App/EvoCommands.swift`
- `evo/Core/BrowserEngine/Scripts/OraBrowserScripts.swift` → `.../EvoBrowserScripts.swift`
- `evo/Shared/Components/Buttons/OraButton.swift` → `.../EvoButton.swift`
- `evo/Shared/Components/Icons/OraIcon.swift` → `.../EvoIcon.swift`
- `evo/Shared/Components/Inputs/OraInput.swift` → `.../EvoInput.swift`
- `evoTests/oraTests.swift` → `evoTests/evoTests.swift`

**Interfaces:**
- Produces (renamed types later tasks/consumers rely on): `EvoApp`, `EvoRoot`, `EvoCommands`, `EvoBrowserScripts`, `EvoButton`/`EvoButtonVariant`/`EvoButtonSize`, `EvoInput`/`EvoInputVariant`, `EvoIcons`/`EvoIconType`/`EvoIconSize`, `EvoWindowDragGesture`, `EvoShortcutHelpModifier`, `EvoKeyboardShortcutModifier`, `EvoTests`.
- Produces (renamed funcs/modifiers): `.evoShortcut(_:)`, `.evoShortcutHelp(...)`, `BrowserPageConfiguration.evoDefault(...)`, `ModelConfiguration.evoDatabase(...)`, `createEvoContainer(...)`.
- Does NOT touch the string literals `"OraColorLogo"` / `"ora-logo-plain"` — those are asset names handled in Task 2.

- [ ] **Step 1: Replace capitalized type identifiers repo-wide**

Run from repo root:

```bash
grep -rlE '\bOra[A-Za-z]' evo evoTests --include='*.swift' | xargs perl -pi -e '
s/\bOraApp\b/EvoApp/g;
s/\bOraRoot\b/EvoRoot/g;
s/\bOraCommands\b/EvoCommands/g;
s/\bOraBrowserScripts\b/EvoBrowserScripts/g;
s/\bOraButtonVariant\b/EvoButtonVariant/g;
s/\bOraButtonSize\b/EvoButtonSize/g;
s/\bOraButton\b/EvoButton/g;
s/\bOraInputVariant\b/EvoInputVariant/g;
s/\bOraInput\b/EvoInput/g;
s/\bOraIconType\b/EvoIconType/g;
s/\bOraIconSize\b/EvoIconSize/g;
s/\bOraIcons\b/EvoIcons/g;
s/\bOraWindowDragGesture\b/EvoWindowDragGesture/g;
s/\bOraShortcutHelpModifier\b/EvoShortcutHelpModifier/g;
s/\bOraKeyboardShortcutModifier\b/EvoKeyboardShortcutModifier/g;
s/\bOraTests\b/EvoTests/g;
'
```

Note: `"OraColorLogo"` is a string literal, not in this list — it is intentionally left for Task 2.

- [ ] **Step 2: Replace lowercase and embedded identifiers**

```bash
grep -rlE '\bora[A-Z]|createOraContainer' evo evoTests --include='*.swift' | xargs perl -pi -e '
s/\boraShortcutHelp\b/evoShortcutHelp/g;
s/\boraShortcut\b/evoShortcut/g;
s/\boraDefault\b/evoDefault/g;
s/\boraDatabase\b/evoDatabase/g;
s/\boraTests\b/evoTests/g;
s/createOraContainer/createEvoContainer/g;
'
```

- [ ] **Step 3: Verify no Ora Swift identifiers remain (except asset strings)**

```bash
grep -rnE '\bOra[A-Za-z]|\bora[A-Z]|createOraContainer' evo evoTests --include='*.swift'
```

Expected: only lines containing the string literals `Image("OraColorLogo")` (in `EvoRoot.swift`) and any `"ora-logo-plain"`-style asset strings. No type/func identifiers. If a bare `Ora*` identifier appears, add it to Step 1's list and re-run.

- [ ] **Step 4: Rename the source files**

```bash
git mv evo/App/OraApp.swift evo/App/EvoApp.swift
git mv evo/App/OraRoot.swift evo/App/EvoRoot.swift
git mv evo/App/OraCommands.swift evo/App/EvoCommands.swift
git mv evo/Core/BrowserEngine/Scripts/OraBrowserScripts.swift evo/Core/BrowserEngine/Scripts/EvoBrowserScripts.swift
git mv evo/Shared/Components/Buttons/OraButton.swift evo/Shared/Components/Buttons/EvoButton.swift
git mv evo/Shared/Components/Icons/OraIcon.swift evo/Shared/Components/Icons/EvoIcon.swift
git mv evo/Shared/Components/Inputs/OraInput.swift evo/Shared/Components/Inputs/EvoInput.swift
git mv evoTests/oraTests.swift evoTests/evoTests.swift
```

- [ ] **Step 5: Regenerate the Xcode project**

```bash
xcodegen
```

Expected: `Loaded project ... Created project at .../Evo.xcodeproj`.

- [ ] **Step 6: Build**

```bash
./scripts/xcbuild-debug.sh
```

Expected: ends with `Build Succeeded` (via xcbeautify), exit 0.

- [ ] **Step 7: Run the test suite (covers OraTests → EvoTests)**

```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO | xcbeautify
```

Expected: `** TEST SUCCEEDED **`. (If the suite is empty/trivial, a passing/zero-test result is acceptable — the goal is that the renamed test target compiles and links.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "♻️ (Swift): rename Ora* symbols and source files to Evo*"
```

---

### Task 2: Rename in-catalog image assets and swap in Evo art

**Files:**
- Rename dirs (`git mv`) under `evo/Assets/Catalogs/Assets.xcassets/`:
  - `OraColorLogo.imageset` → `EvoColorLogo.imageset`
  - `ora-logo-plain.imageset` → `evo-logo-plain.imageset`
  - `ora-logo-outline.imageset` → `evo-logo-outline.imageset`
- Modify: each renamed imageset's `Contents.json`; `appearance-system.imageset/Contents.json` (dir name unchanged — already Evo-neutral) and its inner file.
- Modify (Swift string refs): `evo/App/EvoRoot.swift` (line ~161), `evo/Features/Browser/Views/HomeView.swift` (line ~35).
- Art source: `evo/Assets/Icons/EvoIcon.icon/Assets/EvoLogo.svg` (present today as `OraIcon.icon/Assets/EvoLogo.svg`; if Task 3 has not run yet it is still under `OraIcon.icon` — copy from wherever it currently lives).

**Interfaces:**
- Produces asset names later referenced by string: `"EvoColorLogo"`, `"evo-logo-plain"`, `"evo-logo-outline"` (orphan, no code ref), `"appearance-system"` (unchanged).

- [ ] **Step 1: Rename the three imageset directories**

```bash
cd evo/Assets/Catalogs/Assets.xcassets
git mv OraColorLogo.imageset EvoColorLogo.imageset
git mv ora-logo-plain.imageset evo-logo-plain.imageset
git mv ora-logo-outline.imageset evo-logo-outline.imageset
cd -
```

- [ ] **Step 2: Swap home-screen logo art (`evo-logo-plain`)**

Replace the Ora glyph SVG with the existing Evo logo art, then update `Contents.json`.

```bash
cd evo/Assets/Catalogs/Assets.xcassets/evo-logo-plain.imageset
git rm "Ora Browser Logo.svg"
cp ../../../Icons/OraIcon.icon/Assets/EvoLogo.svg evo-logo-plain.svg
git add evo-logo-plain.svg
cd -
```

Write `evo/Assets/Catalogs/Assets.xcassets/evo-logo-plain.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "evo-logo-plain.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Swap window profile-icon art (`EvoColorLogo`)**

Collapse the light/dark PNG pair into the single Evo SVG (EvoLogo is appearance-adaptive; the separate dark asset is no longer needed).

```bash
cd evo/Assets/Catalogs/Assets.xcassets/EvoColorLogo.imageset
git rm "ora-color-logo.png" "ora-color-logo 1.png"
cp ../../../Icons/OraIcon.icon/Assets/EvoLogo.svg evo-color-logo.svg
git add evo-color-logo.svg
cd -
```

Write `evo/Assets/Catalogs/Assets.xcassets/EvoColorLogo.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "evo-color-logo.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 4: Rename the outline logo file (orphan asset, kept for consistency)**

```bash
cd evo/Assets/Catalogs/Assets.xcassets/evo-logo-outline.imageset
git mv "Ora Browser Logo (1).svg" "evo-logo-outline.svg"
cd -
```

Write `evo/Assets/Catalogs/Assets.xcassets/evo-logo-outline.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "evo-logo-outline.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Rename the appearance-preview file (keep pixels, keep imageset name)**

```bash
cd evo/Assets/Catalogs/Assets.xcassets/appearance-system.imageset
git mv "Ora Browser System.png" "evo-appearance-system.png"
cd -
```

Write `evo/Assets/Catalogs/Assets.xcassets/appearance-system.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "evo-appearance-system.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

(The Swift ref `imageName: "appearance-system"` in `AppearanceSelector.swift` is unchanged — the imageset name did not change.)

- [ ] **Step 6: Update the two Swift asset string references**

In `evo/App/EvoRoot.swift`, change:

```swift
iconImage: Image("OraColorLogo"),
```

to:

```swift
iconImage: Image("EvoColorLogo"),
```

In `evo/Features/Browser/Views/HomeView.swift`, change:

```swift
Image("ora-logo-plain")
```

to:

```swift
Image("evo-logo-plain")
```

- [ ] **Step 7: Build**

```bash
./scripts/xcbuild-debug.sh
```

Expected: `Build Succeeded`, exit 0. (Asset catalogs are folder resources — no `xcodegen` needed for imageset renames.)

- [ ] **Step 8: Sanity-check the asset refs resolve**

```bash
grep -rnE 'Image\("(OraColorLogo|ora-logo-plain)"\)' evo --include='*.swift'
```

Expected: no output (both old names gone).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "🎨 (Assets): rename in-app logo imagesets to Evo* and swap in Evo art"
```

---

### Task 3: Rename app-icon assets and entitlements; update project.yml

**Files:**
- Rename dirs (`git mv`):
  - `evo/Assets/Catalogs/Assets.xcassets/OraIcon.appiconset` → `EvoIcon.appiconset`
  - `evo/Assets/Catalogs/Assets.xcassets/OraIconDev.appiconset` → `EvoIconDev.appiconset`
  - `evo/Assets/Icons/OraIcon.icon` → `evo/Assets/Icons/EvoIcon.icon`
  - `evo/Assets/Icons/OraIconDev.icon` → `evo/Assets/Icons/EvoIconDev.icon`
- Rename inner file: `EvoIcon.appiconset/ora-white-macos-icon.png` → `evo-white-macos-icon.png` (+ same in `EvoIconDev.appiconset` if present).
- Rename entitlements: `evo/Info/ora.entitlements` → `evo.entitlements`; `evo/Info/ora-debug.entitlements` → `evo-debug.entitlements`.
- Modify: `project.yml`; the renamed `.appiconset/Contents.json` files.

**Interfaces:**
- Consumes: `EvoIcon.icon/Assets/EvoLogo.svg` was read by Task 2; that path is now `EvoIcon.icon/Assets/EvoLogo.svg` after this task (Task 2 already copied the file out, so no ordering dependency remains).
- Produces: app-icon set names `EvoIcon` / `EvoIconDev` (referenced by `ASSETCATALOG_COMPILER_APPICON_NAME`).

- [ ] **Step 1: Rename the app-icon sets and dev/release icon bundles**

```bash
cd evo/Assets/Catalogs/Assets.xcassets
git mv OraIcon.appiconset EvoIcon.appiconset
git mv OraIconDev.appiconset EvoIconDev.appiconset
cd -
git mv evo/Assets/Icons/OraIcon.icon evo/Assets/Icons/EvoIcon.icon
git mv evo/Assets/Icons/OraIconDev.icon evo/Assets/Icons/EvoIconDev.icon
```

- [ ] **Step 2: Rename the Ora-named icon file inside the appiconsets**

```bash
cd evo/Assets/Catalogs/Assets.xcassets/EvoIcon.appiconset
git mv "ora-white-macos-icon.png" "evo-white-macos-icon.png"
cd -
# Repeat for the Dev set only if it contains an ora-white-macos-icon.png:
if [ -f "evo/Assets/Catalogs/Assets.xcassets/EvoIconDev.appiconset/ora-white-macos-icon.png" ]; then
  git mv "evo/Assets/Catalogs/Assets.xcassets/EvoIconDev.appiconset/ora-white-macos-icon.png" \
         "evo/Assets/Catalogs/Assets.xcassets/EvoIconDev.appiconset/evo-white-macos-icon.png"
fi
```

- [ ] **Step 3: Update the appiconset Contents.json filename**

In `evo/Assets/Catalogs/Assets.xcassets/EvoIcon.appiconset/Contents.json`, change the one Ora-named entry:

```json
      "filename" : "ora-white-macos-icon.png",
```

to:

```json
      "filename" : "evo-white-macos-icon.png",
```

(Leave the generic `Icon-*.png` entries untouched. Apply the same edit to `EvoIconDev.appiconset/Contents.json` only if Step 2 renamed a file there.)

- [ ] **Step 4: Rename the entitlements files**

```bash
git mv evo/Info/ora.entitlements evo/Info/evo.entitlements
git mv evo/Info/ora-debug.entitlements evo/Info/evo-debug.entitlements
```

- [ ] **Step 5: Update project.yml — entitlements path**

In `project.yml`, replace all three occurrences of `evo/Info/ora.entitlements` with `evo/Info/evo.entitlements` (the `entitlements.path` at ~line 93 and `CODE_SIGN_ENTITLEMENTS` under both Debug ~line 129 and Release ~line 136):

```bash
perl -pi -e 's{evo/Info/ora\.entitlements}{evo/Info/evo.entitlements}g' project.yml
```

- [ ] **Step 6: Update project.yml — app-icon names**

Change `ASSETCATALOG_COMPILER_APPICON_NAME: OraIconDev` → `EvoIconDev` (Debug) and `ASSETCATALOG_COMPILER_APPICON_NAME: OraIcon` → `EvoIcon` (Release):

```bash
perl -pi -e 's{ASSETCATALOG_COMPILER_APPICON_NAME: OraIconDev}{ASSETCATALOG_COMPILER_APPICON_NAME: EvoIconDev}g; s{ASSETCATALOG_COMPILER_APPICON_NAME: OraIcon\b}{ASSETCATALOG_COMPILER_APPICON_NAME: EvoIcon}g' project.yml
```

- [ ] **Step 7: Update project.yml — Copy Icon Bundle preBuildScript**

Replace every `OraIcon.icon` / `OraIconDev.icon` with `EvoIcon.icon` / `EvoIconDev.icon` in the preBuildScript block (inputFiles, outputFiles, and the shell script body: `ICON_SRC_DEV`, `ICON_SRC_RELEASE`, echo lines):

```bash
perl -pi -e 's{OraIconDev\.icon}{EvoIconDev.icon}g; s{OraIcon\.icon}{EvoIcon.icon}g' project.yml
```

- [ ] **Step 8: Verify no Ora refs remain in project.yml**

```bash
grep -niE 'ora' project.yml
```

Expected: no output.

- [ ] **Step 9: Regenerate and build**

```bash
xcodegen && ./scripts/xcbuild-debug.sh
```

Expected: project regenerates; `Build Succeeded`, exit 0. (If the build warns about a missing app icon, confirm `ASSETCATALOG_COMPILER_APPICON_NAME` matches the renamed `.appiconset` dir name exactly.)

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "♻️ (icons, entitlements, project.yml): rename app-icon assets and entitlements to Evo*"
```

---

### Task 4: Delete dead upstream-rebase machinery

**Files (delete):**
- `FORK_PATCHES.md`
- `appcast.xml`, `ora_public_key.pem`
- `scripts/build.sh`, `scripts/release.sh`, `scripts/publish.sh`, `scripts/_common.sh`, `scripts/generate-changelog.py`, `scripts/prompts/` (contains `changelog_prompt.txt`)

**Keep:** `scripts/xcbuild-debug.sh`.

- [ ] **Step 1: Confirm nothing references the release scripts**

```bash
grep -rnE 'build\.sh|release\.sh|publish\.sh|_common\.sh|generate-changelog|appcast\.xml|ora_public_key|FORK_PATCHES' \
  --include='*.sh' --include='*.yml' --include='*.swift' --include='*.md' . 2>/dev/null \
  | grep -v 'docs/superpowers' | grep -v xcbuild-debug
```

Expected: references appear only inside docs about to be rewritten in Task 5 (`README.md`, `CLAUDE.md`, `BUILD.md`, `SECURITY.md`) — those are handled next. No hook, CI, or script actively invokes them.

- [ ] **Step 2: Delete the files**

```bash
git rm FORK_PATCHES.md appcast.xml ora_public_key.pem \
  scripts/build.sh scripts/release.sh scripts/publish.sh scripts/_common.sh \
  scripts/generate-changelog.py
git rm -r scripts/prompts
```

- [ ] **Step 3: Confirm the dev build path survives**

```bash
ls scripts/
./scripts/xcbuild-debug.sh
```

Expected: `scripts/` still contains `xcbuild-debug.sh`; `Build Succeeded`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "🔥 (scripts, root): delete upstream-rebase release pipeline and Sparkle artifacts"
```

---

### Task 5: Rewrite docs down to the GPL attribution floor

**Files (modify):**
- `CLAUDE.md` — strip fork/rebase guidance; describe Evo as standalone; keep architecture/commands/style.
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `ROADMAP.md`, `BUILD.md` (if present) — trim fork framing to the GPL attribution line; remove references to deleted scripts/`FORK_PATCHES.md`.
- `LICENSE` — untouched (verify only).

**Interfaces:** none (docs).

- [ ] **Step 1: Inventory remaining Ora prose across docs**

```bash
grep -rniE 'ora|fork_patches|the-ora|orabrowser|rebase' \
  README.md CONTRIBUTING.md SECURITY.md ROADMAP.md CLAUDE.md BUILD.md 2>/dev/null
```

Use the output as the worklist for the edits below.

- [ ] **Step 2: Rewrite CLAUDE.md**

Remove, in `CLAUDE.md`:
- The sentence in "What this is" stating internal names stay `Ora` and to "re-apply that list after every rebase on upstream" — replace with a standalone description ending in the GPL note (see Step 4 wording).
- The `FORK_PATCHES.md` naming-policy references throughout (e.g. the `evo/App/` bullet's "see FORK_PATCHES.md for the internal-vs-user-facing naming policy" — the policy no longer exists; identifiers are now `Evo*`).
- The Commands-section paragraph warning that `scripts/build.sh`/`release.sh`/`publish.sh` reference `com.orabrowser.app` etc. — those scripts are deleted; remove the paragraph.
- The "Sparkle is disabled on this fork" paragraph's instruction not to reintroduce Ora's appcast on rebase — Sparkle stays disabled, but drop the rebase/appcast-file wording (the files are deleted).
- Update `Ora*` type names cited in the "Source layout" section (`OraApp`, `OraRoot`, `OraCommands`) to `EvoApp`, `EvoRoot`, `EvoCommands`.

Keep all still-accurate architecture, XcodeGen commands (minus deleted scripts), test-layout, WKWebView, and style sections.

- [ ] **Step 3: Trim README.md / CONTRIBUTING.md / SECURITY.md / ROADMAP.md / BUILD.md**

- Remove "tracks upstream Ora closely", "personal fork of", and links presenting the project as a live fork, EXCEPT the single GPL attribution line (Step 4).
- Remove any mention of `FORK_PATCHES.md` and the deleted `scripts/build.sh`/`release.sh`/`publish.sh` (e.g. SECURITY.md's "upstream release scripts … not safe to run" bullet, BUILD.md references).
- Keep ROADMAP.md's forward-looking MCP/AI content.

- [ ] **Step 4: Ensure the GPL attribution floor is present**

`README.md` must retain exactly one attribution line, e.g.:

```markdown
Evo is a standalone macOS browser derived from [Ora Browser](https://github.com/the-ora/browser), licensed under [GPL-3.0](LICENSE). Upstream copyright is retained; modifications © SK Productions LLC.
```

Verify `LICENSE` is unchanged:

```bash
git diff --name-only | grep -x LICENSE || echo "LICENSE untouched (good)"
```

Expected: `LICENSE untouched (good)`.

- [ ] **Step 5: Final repo-wide verification**

```bash
grep -rniE '\bora' evo evoTests project.yml --include='*.swift' --include='*.yml' \
  | grep -viE 'storage|decorator|temporary|corala|aurora|memora|categor|collabora|explora|orative' \
  | grep -v 'mark.js'
```

Expected: no output (all Ora identifiers/asset refs gone from code + build config).

```bash
grep -rniE '\bora\b|orabrowser|the-ora' *.md 2>/dev/null | grep -viE 'docs/superpowers'
```

Expected: only the single GPL attribution line(s) in `README.md` (and identical attribution if repeated in CONTRIBUTING/SECURITY). No rebase/FORK_PATCHES/appcast prose.

- [ ] **Step 6: Final build + test**

```bash
xcodegen && ./scripts/xcbuild-debug.sh && \
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO | xcbeautify
```

Expected: `Build Succeeded` and `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "📝 (docs): rewrite for standalone Evo; keep GPL attribution floor"
```

---

## Self-Review

**Spec coverage:**
- Swift symbols (§1) → Task 1. ✅
- Assets + art swap (§2) → Task 2 (imagesets) + Task 3 (app-icon sets/bundles). ✅
- Build config + entitlements (§3) → Task 3. ✅
- Deletions (§4) → Task 4. ✅
- Docs (§5) → Task 5. ✅
- GPL floor (hard constraint) → Global Constraints + Task 5 Step 4. ✅
- Verification/success criteria (§verification) → Task 5 Steps 5–6 (clean build, test, grep returns only Mark.js + GPL line). ✅
- No-data-orphaning finding → Global Constraints. ✅

**Placeholder scan:** No TBD/TODO; every code/command step shows exact content and expected output. ✅

**Type consistency:** Renamed symbols in Task 1's Interfaces block (`EvoRoot`, `EvoColorLogo` string) match their downstream use in Task 2 Step 6 (`Image("EvoColorLogo")` in `EvoRoot.swift`) and Task 5 Step 2 (CLAUDE.md cites `EvoApp`/`EvoRoot`/`EvoCommands`). App-icon names `EvoIcon`/`EvoIconDev` are consistent between the `.appiconset` renames (Task 3 Step 1) and `ASSETCATALOG_COMPILER_APPICON_NAME` (Task 3 Step 6). ✅

**Note on TDD:** This is a mechanical rename of existing, tested code — there is no new behavior to test-drive. The per-task gate is a green Debug build (compiler as the test) plus the existing test suite in Tasks 1 and 5, plus grep-based completeness checks. This is the honest verification loop for a rename; fabricated unit tests would add no signal.
