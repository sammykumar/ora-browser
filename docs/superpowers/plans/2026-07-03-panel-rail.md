# Right-Edge Panel Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ~40pt vertical icon rail at the right edge of every Evo window that toggles side panels (Claude first) with radio semantics, backed by an enum registry so future panels are one case + one view.

**Architecture:** A new per-window `PanelRailManager` (replacing `ClaudePanelManager`) holds `activePanel: SidePanel?` plus the existing `SideHolder`/`FractionHolder`; `PanelRailView` renders `SidePanel.allCases` as buttons and sits as the trailing sibling of `BrowserSplitView` inside `BrowserView`'s ZStack base layer. The shipped nested-HSplit hide mechanism is untouched — the rail only drives it.

**Tech Stack:** Swift 6.3 / SwiftUI, macOS 15.0, vendored SplitView (`SideHolder`/`FractionHolder`/`HSplit`), Swift Testing. XcodeGen (`xcodegen` after adding files); build via `./scripts/xcbuild-debug.sh`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-03-panel-rail-design.md`. Work on branch **`feat/panel-rail`** (created in Task 1 from `main`).
- **Preserve the UserDefaults key `claude.panel.fraction`** (panel width must survive this refactor) and the `SideHolder(.secondary)` closed-by-default, non-persisted visibility semantics.
- **Radio semantics:** at most one panel open; swap keeps the side shown and switches slot content.
- **Rail visibility** is app-wide `@AppStorage("rail.isVisible")`, default `true`.
- **Do not modify** `ClaudeChatManager`, `ClaudeSidePanelView` internals, or anything under `evo/Core/Claude/`.
- ⌥⌘C / `.toggleClaudePanel` notification must keep working; EvoRoot observers filter by `note.object as? NSWindow === window` (codebase invariant).
- SwiftLint bans `force_unwrapping`/`implicitly_unwrapped_optional`; SwiftFormat 4-space, 120-col, `--self remove`. Run `swiftformat .` and `swiftlint lint --fix --use-alternative-excluding` before each commit; commit ONLY task files.
- Tests: Swift Testing (`import Testing`), plain `struct` suites, `@testable import Evo`, files under `evoTests/PanelRail/`. Focused runs only — **NEVER run `evoTests/EvoToolServerSmokeTests`** (it makes a billed API call): always pass `-skip-testing:evoTests/EvoToolServerSmokeTests` when running anything broader than one suite.
- After adding new files run `xcodegen` before building.

## File Structure

**Create:**
- `evo/Features/PanelRail/Models/SidePanel.swift` — the enum registry (id/title/symbol/shortcutHint). (Task 2)
- `evo/Features/PanelRail/State/PanelRailManager.swift` — per-window manager: `activePanel`, holders, rail visibility, `toggle(_:)`. (Task 2)
- `evo/Features/PanelRail/Views/PanelRailButton.swift` — one icon button (active state, tooltip, activity dot). (Task 4)
- `evo/Features/PanelRail/Views/PanelRailView.swift` — the rail strip. (Task 4)
- `evoTests/PanelRail/PanelRailManagerTests.swift` — toggle-semantics tests. (Task 2)

**Modify:**
- `evo/App/EvoRoot.swift:27,113,239-243` — construct/inject `PanelRailManager`; rewire `.toggleClaudePanel` observer; add `.togglePanelRail` observer. (Tasks 3, 5)
- `evo/Features/Browser/Views/BrowserSplitView.swift:9,84-90` — env object swap; `contentView()` slot switch. (Task 3)
- `evo/Features/Browser/Views/BrowserView.swift:65-67` — wrap base layer in `HStack { BrowserSplitView(); PanelRailView() }`. (Task 4)
- `evo/App/EvoCommands.swift:90-94` — add "Hide/Show Panel Rail" menu item. (Task 5)
- `evo/Core/Constants/AppEvents.swift:20` — add `.togglePanelRail`. (Task 5)

**Delete:**
- `evo/Features/Claude/State/ClaudePanelManager.swift` (superseded — Task 3)

---

### Task 1: Branch setup

**Files:** none (git only).

**Interfaces:**
- Produces: branch `feat/panel-rail` at `main`'s tip; all later tasks commit here.

- [ ] **Step 1: Create the branch**

```bash
cd /Users/samkumar/Development/SK-Productions-LLC/evo-browser
git checkout main && git status --short   # expect clean (untracked files OK)
git checkout -b feat/panel-rail
git branch --show-current                  # expect: feat/panel-rail
```

No commit (nothing changed). Task complete when the branch is current.

---

### Task 2: `SidePanel` registry + `PanelRailManager` (TDD)

**Files:**
- Create: `evo/Features/PanelRail/Models/SidePanel.swift`
- Create: `evo/Features/PanelRail/State/PanelRailManager.swift`
- Test: `evoTests/PanelRail/PanelRailManagerTests.swift`

**Interfaces:**
- Produces: `enum SidePanel: String, CaseIterable, Identifiable { case claude; var id: String; var title: String; var symbol: String; var shortcutHint: String }`
- Produces: `@MainActor final class PanelRailManager: ObservableObject { @Published private(set) var activePanel: SidePanel?; let hiddenPanel: SideHolder; let fraction: FractionHolder; func toggle(_ panel: SidePanel) }` — plus `@AppStorage("rail.isVisible") var isRailVisible: Bool` (default `true`). Tasks 3–5 consume these names verbatim.
- Consumes: vendored `SideHolder`/`FractionHolder` (already used by the codebase, e.g. the current `ClaudePanelManager`).

- [ ] **Step 1: Write the failing tests**

Create `evoTests/PanelRail/PanelRailManagerTests.swift`:

```swift
import Testing
@testable import Evo

@MainActor struct PanelRailManagerTests {
    @Test func startsClosedAndHidden() {
        let manager = PanelRailManager()
        #expect(manager.activePanel == nil)
        #expect(manager.hiddenPanel.side == .secondary)
    }

    @Test func toggleOpensPanelAndShowsSide() {
        let manager = PanelRailManager()
        manager.toggle(.claude)
        #expect(manager.activePanel == .claude)
        #expect(manager.hiddenPanel.side == nil)
    }

    @Test func toggleSamePanelClosesAndHides() {
        let manager = PanelRailManager()
        manager.toggle(.claude)
        manager.toggle(.claude)
        #expect(manager.activePanel == nil)
        #expect(manager.hiddenPanel.side == .secondary)
    }

    @Test func registryHasStableClaudeMetadata() {
        #expect(SidePanel.claude.id == "claude")
        #expect(SidePanel.claude.symbol == "sparkles")
        #expect(SidePanel.allCases.contains(.claude))
    }
}
```

(Swap-between-panels semantics cannot be tested until a second case exists; the radio invariant is enforced by the single-optional design and documented in code. Do not add a fake test-only enum case.)

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/PanelRailManagerTests
```
Expected: FAIL — `PanelRailManager`/`SidePanel` not found. (If the new test file isn't picked up, run `xcodegen` first.)

- [ ] **Step 3: Implement the registry and manager**

Create `evo/Features/PanelRail/Models/SidePanel.swift`:

```swift
import Foundation

/// The closed registry of side panels shown on the right-edge rail.
/// Adding a panel = add a case here + a view branch in `BrowserSplitView.panelSlot()`
/// (the exhaustive switch there makes forgetting the view a compile error).
enum SidePanel: String, CaseIterable, Identifiable {
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        }
    }

    /// Tooltip hint only — the actual key binding lives in `EvoCommands`.
    var shortcutHint: String {
        switch self {
        case .claude: "⌥⌘C"
        }
    }
}
```

Create `evo/Features/PanelRail/State/PanelRailManager.swift`:

```swift
import SwiftUI

/// Per-window state for the right-edge panel rail (supersedes ClaudePanelManager).
/// Radio semantics: at most one panel open. The nested HSplit in `BrowserSplitView`
/// stays mounted and is hidden/shown via `hiddenPanel`, exactly as before.
@MainActor final class PanelRailManager: ObservableObject {
    /// The open panel, or nil when the slot is closed. Single-optional enforces radio exclusivity.
    @Published private(set) var activePanel: SidePanel?

    /// nil = slot visible; .secondary = hidden. Starts hidden; visibility is per-launch, not persisted.
    let hiddenPanel = SideHolder(.secondary)

    /// Shared slot width. Key kept from the walking skeleton so the user's panel width survives.
    let fraction = FractionHolder.usingUserDefaults(0.7, key: "claude.panel.fraction")

    /// Rail chrome visibility — app-wide by design (View → Hide Panel Rail).
    @AppStorage("rail.isVisible") var isRailVisible = true

    func toggle(_ panel: SidePanel) {
        if activePanel == panel {
            activePanel = nil
            hiddenPanel.side = .secondary
        } else {
            activePanel = panel        // opens, or swaps content while staying shown
            hiddenPanel.side = nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS (4/4).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Features/PanelRail/ evoTests/PanelRail/
git commit -m "feat(rail): SidePanel registry + PanelRailManager with radio toggle"
```

---

### Task 3: Replace `ClaudePanelManager` — rewire EvoRoot + BrowserSplitView

**Files:**
- Delete: `evo/Features/Claude/State/ClaudePanelManager.swift`
- Modify: `evo/App/EvoRoot.swift:27,113,239-243`
- Modify: `evo/Features/Browser/Views/BrowserSplitView.swift:9,84-90`

**Interfaces:**
- Consumes: `PanelRailManager` (Task 2): `activePanel`, `hiddenPanel`, `fraction`, `toggle(.claude)`.
- Produces: env object `railManager: PanelRailManager` injected from EvoRoot; `BrowserSplitView.panelSlot()` slot-switch that Task 4's rail relies on staying exhaustive.

- [ ] **Step 1: Swap the manager in EvoRoot**

In `evo/App/EvoRoot.swift`:
- Line 27: `@StateObject private var claudePanel = ClaudePanelManager()` → `@StateObject private var railManager = PanelRailManager()`
- Line 113: `.environmentObject(claudePanel)` → `.environmentObject(railManager)`
- Lines 239-243 (the `.toggleClaudePanel` observer): replace the body call `claudePanel.toggle()` with `railManager.toggle(.claude)`. Keep the notification name, the window filter, and the `Task { @MainActor in }` wrapper exactly as they are.

- [ ] **Step 2: Rewire BrowserSplitView and delete the old manager**

In `evo/Features/Browser/Views/BrowserSplitView.swift`:
- Line 9: `@EnvironmentObject var claudePanel: ClaudePanelManager` → `@EnvironmentObject var railManager: PanelRailManager`
- Replace `contentView()` (lines 84-90) with:

```swift
    /// The panel slot is always mounted as the secondary side of a nested HSplit and hidden via
    /// `railManager.hiddenPanel`, mirroring how the outer HSplit above hides the sidebar. This keeps
    /// `webContent()` (and the WKWebView bridge inside it) mounted across every panel toggle.
    private func contentView() -> some View {
        HSplit(left: { webContent() }, right: { panelSlot() })
            .hide(railManager.hiddenPanel)
            .fraction(railManager.fraction)
            .constraints(minPFraction: 0.4, minSFraction: 0.2)
            .styling(hideSplitter: true)
    }

    /// Exhaustive over SidePanel: adding a registry case without a view branch is a compile error.
    /// nil renders the Claude view behind the hidden holder — keeps it mounted so conversation and
    /// composer draft survive close/open (verified shipped behavior).
    @ViewBuilder private func panelSlot() -> some View {
        switch railManager.activePanel {
        case .claude, nil:
            ClaudeSidePanelView(chat: claudeChat)
        }
    }
```

Then delete the superseded file:

```bash
git rm evo/Features/Claude/State/ClaudePanelManager.swift
```

- [ ] **Step 3: Build to verify no dangling references**

```bash
xcodegen && ./scripts/xcbuild-debug.sh
```
Expected: Build Succeeded. If the compiler flags other `claudePanel`/`ClaudePanelManager` references the greps above missed, migrate them to `railManager` the same way and note it in your report.

- [ ] **Step 4: Run the manager tests to confirm nothing regressed**

```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -only-testing:evoTests/PanelRailManagerTests -only-testing:evoTests/ClaudeChatManagerTests
```
Expected: PASS (4 + 3).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/App/EvoRoot.swift evo/Features/Browser/Views/BrowserSplitView.swift
git add -u evo/Features/Claude/State/
git commit -m "refactor(rail): PanelRailManager supersedes ClaudePanelManager"
```

---

### Task 4: `PanelRailView` + docking in BrowserView

**Files:**
- Create: `evo/Features/PanelRail/Views/PanelRailButton.swift`
- Create: `evo/Features/PanelRail/Views/PanelRailView.swift`
- Modify: `evo/Features/Browser/Views/BrowserView.swift:65-67`

**Interfaces:**
- Consumes: `railManager.activePanel/isRailVisible/toggle(_:)` (Task 2/3), `claudeChat.isRunning` (existing), `SidePanel.allCases` metadata.
- Produces: `PanelRailView` (no parameters; reads env objects) — Task 5's menu toggle flips what it observes.

- [ ] **Step 1: Implement the button**

Create `evo/Features/PanelRail/Views/PanelRailButton.swift`:

```swift
import SwiftUI

struct PanelRailButton: View {
    let panel: SidePanel
    let isActive: Bool
    let showsActivityDot: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: panel.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .overlay(alignment: .topTrailing) {
                    if showsActivityDot {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(.plain)
        .help("\(panel.title)  \(panel.shortcutHint)")
        .accessibilityLabel("\(panel.title) panel")
    }
}
```

- [ ] **Step 2: Implement the rail**

Create `evo/Features/PanelRail/Views/PanelRailView.swift`:

```swift
import SwiftUI

/// The right-edge vertical icon rail. Window chrome: outermost trailing element,
/// full height, one button per registered SidePanel.
struct PanelRailView: View {
    @EnvironmentObject private var railManager: PanelRailManager
    @EnvironmentObject private var claudeChat: ClaudeChatManager

    var body: some View {
        if railManager.isRailVisible {
            VStack(spacing: 6) {
                ForEach(SidePanel.allCases) { panel in
                    PanelRailButton(
                        panel: panel,
                        isActive: railManager.activePanel == panel,
                        showsActivityDot: activityDot(for: panel),
                        action: { withAnimation { railManager.toggle(panel) } }
                    )
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .frame(width: 40)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
        }
    }

    /// A long-running Claude turn stays visible when its panel is closed.
    private func activityDot(for panel: SidePanel) -> Bool {
        panel == .claude && claudeChat.isRunning && railManager.activePanel != .claude
    }
}
```

- [ ] **Step 3: Dock the rail in BrowserView**

In `evo/Features/Browser/Views/BrowserView.swift`, the base layer of the ZStack (lines 66-67) currently starts:

```swift
        ZStack(alignment: .top) {
            BrowserSplitView()
                .ignoresSafeArea(.all)
```

Wrap the split and the rail in an HStack so the rail is the outermost trailing element while all existing modifiers/overlays keep applying to the same base layer. The `BrowserSplitView()` call and its entire modifier chain (`.ignoresSafeArea`, `.background(...)`, `.overlay { ... }`, etc.) move inside unchanged:

```swift
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                BrowserSplitView()
                    .ignoresSafeArea(.all)
                    // ... existing modifier chain stays attached to BrowserSplitView, unchanged ...
                PanelRailView()
                    .ignoresSafeArea(.all)
            }
```

Judgment note: if any existing modifier on `BrowserSplitView` is clearly window-scoped rather than split-scoped (e.g. a full-window background), attaching it to the `HStack` instead is acceptable — decide by reading the modifier chain, preserve visual behavior, and document the choice in your report.

- [ ] **Step 4: Build and launch-check**

```bash
xcodegen && ./scripts/xcbuild-debug.sh
open ~/Library/Developer/Xcode/DerivedData/Evo-epztndcgnuviwlbtqluplsstlrjh/Build/Products/Debug/Evo.app
sleep 5 && pkill -f "Evo.app/Contents/MacOS/Evo"
```
Expected: Build Succeeded; app launches without crash (launch by that explicit DerivedData path — a bare `Evo-*` glob has matched stale build dirs before). Do NOT type prompts (billed).

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Features/PanelRail/Views/ evo/Features/Browser/Views/BrowserView.swift
git commit -m "feat(rail): right-edge icon rail docked in BrowserView"
```

---

### Task 5: Menu item + notification for rail visibility

**Files:**
- Modify: `evo/Core/Constants/AppEvents.swift:20` (add name below `.toggleClaudePanel`)
- Modify: `evo/App/EvoCommands.swift:90-94` (add item after the Toggle Claude Panel button)
- Modify: `evo/App/EvoRoot.swift` (add observer next to the `.toggleClaudePanel` one, ~line 239)

**Interfaces:**
- Consumes: `railManager.isRailVisible` (Task 2).
- Produces: `Notification.Name.togglePanelRail`; View menu item "Hide Panel Rail".

- [ ] **Step 1: Add the notification name**

In `evo/Core/Constants/AppEvents.swift`, below line 20:

```swift
    static let togglePanelRail = Notification.Name("TogglePanelRail")
```

- [ ] **Step 2: Add the menu item**

In `evo/App/EvoCommands.swift`, directly after the Toggle Claude Panel button (after line 93):

```swift
            Button("Hide Panel Rail") {
                NotificationCenter.default.post(name: .togglePanelRail, object: NSApp.keyWindow)
            }
```

(No keyboard shortcut — spec lists remappable rail shortcuts as out of scope. A static title is acceptable: `EvoCommands` has no access to per-window state, and `isRailVisible` is app-wide `@AppStorage`; if a dynamic Hide/Show title is trivially achievable with `@AppStorage("rail.isVisible")` read directly in `EvoCommands`, do it and note it — otherwise keep the static title and note that.)

- [ ] **Step 3: Add the observer in EvoRoot**

Next to the `.toggleClaudePanel` observer (~line 239), following the identical pattern (window filter + `Task { @MainActor in }`):

```swift
                NotificationCenter.default.addObserver(forName: .togglePanelRail, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window else { return }
                    Task { @MainActor in
                        railManager.isRailVisible.toggle()
                    }
                }
```

(Match the exact observer idiom used in the surrounding lines — if the existing observers capture `window` differently or use a helper, mirror it.)

- [ ] **Step 4: Build + focused tests**

```bash
./scripts/xcbuild-debug.sh
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -only-testing:evoTests/PanelRailManagerTests
```
Expected: Build Succeeded; 4/4 pass.

- [ ] **Step 5: Commit**

```bash
swiftformat . && swiftlint lint --fix --use-alternative-excluding
git add evo/Core/Constants/AppEvents.swift evo/App/EvoCommands.swift evo/App/EvoRoot.swift
git commit -m "feat(rail): View menu toggle for panel rail visibility"
```

---

### Task 6: Full-suite regression + runtime GUI verification

**Files:** none (verification only; controller executes the GUI portion).

- [ ] **Step 1: Full suite minus the billed smoke test**

```bash
xcodebuild test -scheme evo -destination "platform=macOS" -configuration Debug \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  -skip-testing:evoTests/EvoToolServerSmokeTests
```
Expected: TEST SUCCEEDED (all suites, smoke skipped).

- [ ] **Step 2: Runtime GUI checks (controller-driven, screenshot evidence, window-scoped captures)**

1. Launch by explicit path; rail visible at the window's right edge with the Claude sparkles icon.
2. Click the icon → Claude panel opens in the existing slot; icon shows active highlight.
3. Click again → panel closes; web content reclaims width; icon back to inactive.
4. ⌥⌘C → same behavior as the icon (opens/closes, icon state follows).
5. Regression: type a composer draft, close/open the panel via the icon → draft survives.
6. View → "Hide Panel Rail" → rail collapses; web content full width; View item again → rail returns.
7. (If a prompt is run for any reason it bills — not required for this task; the activity-dot check is deferred to normal use since it requires a live run.)

- [ ] **Step 3: Final commit if verification produced doc/ledger updates only**

```bash
git add -A && git commit -m "docs(rail): runtime verification notes" # only if anything changed
```

---

## Self-Review

**Spec coverage:** placement/HStack docking → T4; always-visible + menu toggle + `rail.isVisible` → T2/T5; radio semantics → T2; enum registry → T2; manager replacement preserving `claude.panel.fraction` + SideHolder semantics → T2/T3; slot switch exhaustiveness → T3; ⌥⌘C compat → T3; activity dot → T4; unit tests → T2; runtime verification incl. draft regression → T6. Out-of-scope items: none built. ✅

**Placeholder scan:** the only elisions are "existing modifier chain stays attached, unchanged" (T4 Step 3 — deliberate: the chain must be preserved verbatim from the file, not transcribed into the plan where it could drift) with an explicit judgment note, and T5's static-vs-dynamic menu title with both outcomes specified. No TBDs. ✅

**Type consistency:** `SidePanel` (claude/id/title/symbol/shortcutHint), `PanelRailManager` (activePanel/hiddenPanel/fraction/isRailVisible/toggle), env name `railManager`, `panelSlot()` — spelled identically across T2–T5. `PanelRailButton(panel:isActive:showsActivityDot:action:)` matches its T4 call site. ✅
