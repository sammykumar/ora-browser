# Evo Browser

Evo is a personal Arc-style browser built on Chromium with a bundled local AI
runtime. This repository is the control plane for the complete Evo workspace:
it pins every component, stores the Evo Chromium patch series, and provides one
set of commands for building and testing the browser.

## Workspace layout

| Path | Purpose | Git ownership |
|---|---|---|
| `evo-chromium/src` | Chromium source and Evo browser shell | depot_tools checkout, ignored here |
| `patches/chromium` | Reviewable Evo commits over the pinned Chromium base | this repository |
| `evo-runtime` | Local runtime, Claude session supervision, policy, and transport | private submodule |
| `evo-opencode` | Evo's externally-agentic OpenCode provider fork | private submodule |
| `docs` | Architecture, migration, EvoWork reference, and backlog | this repository |

Chromium is deliberately not a Git submodule. Its source checkout is large and
uses Chromium's `depot_tools`, `gclient`, and `DEPS` workflow. Evo's changes are
kept as a small patch stack over the exact base recorded in `workspace.json`.

## Set up

```bash
./scripts/bootstrap.sh
./scripts/check-workspace.sh
```

The expected local checkout is `evo-chromium/src`. An existing checkout can be
moved there without rebuilding; a fresh Chromium checkout can be prepared and
then populated with `./scripts/apply-chromium-patches.sh`.

## Develop and test

```bash
./scripts/test.sh
./scripts/build-dev.sh
./scripts/run-dev.sh
```

Codex and automated checks use only **Evo Dev**, its mock keychain, and the
isolated `Evo Chromium Dev` profile. Sam tests the signed production app and
keeps the production profile as the daily dogfooding environment.

```bash
./scripts/install-production.sh
open /Applications/Evo.app
```

## Component changes

Commit and push runtime and OpenCode changes in their own repositories, then
commit the updated submodule pointer here. Commit Chromium changes in the
Chromium checkout, then run:

```bash
./scripts/export-chromium-patches.sh
```

This keeps the root repository reproducible without mixing Chromium's upstream
history into Evo's product history.

## WebKit legacy

The previous SwiftUI/WKWebView application is preserved at tag `webkit-final`
and branch `legacy/webkit`. It is deprecated and is not part of the active
build. See [docs/legacy-webkit.md](docs/legacy-webkit.md).
