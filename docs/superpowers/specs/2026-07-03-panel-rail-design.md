# Right-Edge Panel Rail — Design

_Status: approved (design). Date: 2026-07-03._

## What this is

A vertical icon rail docked at the right edge of every Evo browser window that
toggles side panels. The Claude chat panel (shipped in the walking skeleton,
see `2026-06-30-claude-browser-integration-design.md`) is the first panel; the
rail is built as a small registry so future panels — Chat space, 1Password,
repo sessions, remote-session monitor — plug in by adding one enum case and one
view. Today the Claude panel is reachable only via ⌥⌘C / View menu; the rail
gives every panel a visible, discoverable affordance.

## Decisions (settled with Sam)

- **Placement: window edge, always.** The rail is the outermost trailing
  element of the window, full height, regardless of where the tabs sidebar is
  docked. With a right-docked sidebar the order is `content | sidebar | rail`.
  The rail reads as window chrome (Edge/Arc convention).
- **Visibility: always visible, menu-toggleable.** Standing chrome like the
  toolbar, with View → "Hide Panel Rail" for zero-chrome mode. The preference
  is app-wide (`@AppStorage`), not per-window.
- **Exclusivity: one panel at a time.** Radio semantics — clicking a panel's
  icon toggles it; clicking a different icon swaps content in the same slot.
  Multi-panel stacking is a possible later evolution, not built now.
- **Registry shape: enum, not protocol.** `enum SidePanel: CaseIterable` with
  computed metadata. A closed, owner-controlled set; adding a panel is one case
  + one view. No dynamic registration indirection (rejected as enterprise
  overhead for a personal app). Hardcoding a single Claude button with no
  registry was rejected because the multi-panel roadmap is explicit.

## Architecture

```
EvoRoot (per window)
  └─ BrowserView
       ZStack {                                  ← overlays still span full window
         HStack(spacing: 0) {
           BrowserSplitView()                    ← unchanged outer sidebar split
             └─ contentView(): HSplit(web │ panel slot)   ← unchanged mechanism
           PanelRailView()                       ← NEW, ~40pt, full height
         }
         FloatingSidebarOverlay / FloatingURLBar / LauncherView / …
       }
```

The rail never moves or resizes the existing splits; it only drives the
already-shipped hidden-side mechanism (`SideHolder` + always-mounted `HSplit`).

## Components

### 1. `SidePanel` (the registry) — `evo/Features/PanelRail/Models/SidePanel.swift`

```swift
enum SidePanel: String, CaseIterable, Identifiable {
    case claude

    var id: String { rawValue }
    var title: String { ... }        // "Claude"
    var symbol: String { ... }       // "sparkles"
    var shortcutHint: String { ... } // "⌥⌘C" (tooltip text only; bindings stay where they are)
}
```

Adding a future panel = one new case (+ its view in the slot switch, §4).

### 2. `PanelRailManager` — `evo/Features/PanelRail/State/PanelRailManager.swift`

Per-window `@MainActor final class … : ObservableObject`, constructed in
`EvoRoot.init` and injected via `.environmentObject`. **Replaces and deletes
`ClaudePanelManager`.**

- `@Published private(set) var activePanel: SidePanel?` — stored + published
  (this also retires the ledger finding that the old computed `isVisible`
  never fired `objectWillChange`; the rail icons are exactly the consumers
  that finding predicted).
- `let hiddenPanel = SideHolder(.secondary)` and
  `let fraction = FractionHolder.usingUserDefaults(0.7, key: "claude.panel.fraction")`
  — carried over unchanged so the user's panel width survives this refactor.
  Per-panel fractions become relevant only when a second panel exists; until
  then one holder is shared (YAGNI).
- `@AppStorage("rail.isVisible") var isRailVisible = true` (app-wide).
- `func toggle(_ panel: SidePanel)` — radio semantics:
  - `activePanel == panel` → close (set `nil`, hide side)
  - `activePanel == nil` → open `panel`
  - otherwise → swap `activePanel` (side stays shown; slot content switches)
- Visibility of the panel slot is derived: `hiddenPanel.side` is `.secondary`
  iff `activePanel == nil`.

### 3. `PanelRailView` + `PanelRailButton` — `evo/Features/PanelRail/Views/`

- ~40pt wide, full window height, trailing edge; background material and item
  styling matched to Evo's sidebar items (verify against `SidebarView`
  conventions during implementation).
- Icons top-aligned, one `PanelRailButton` per `SidePanel.allCases`.
- Active state: accent tint + filled rounded background. Tooltip:
  `"\(title)  \(shortcutHint)"`.
- **Claude activity dot:** a small badge on the Claude icon when
  `claudeChat.isRunning && activePanel != .claude` — a long agent run stays
  visible after the panel is hidden.
- Hidden entirely when `isRailVisible == false` (the HStack collapses; web
  content reclaims the width).

### 4. Panel slot content — `BrowserSplitView.contentView()`

The inner `HSplit`'s right side becomes a switch over the active panel:

```swift
HSplit(left: { webContent() }, right: { panelSlot() })
    .hide(railManager.hiddenPanel)
    ...

@ViewBuilder private func panelSlot() -> some View {
    switch railManager.activePanel {
    case .claude, nil: ClaudeSidePanelView(chat: claudeChat)
    }
}
```

(`nil` renders the Claude view behind the hidden holder — identical to today's
behavior, keeps the view mounted so composer draft/conversation state survive
open/close, which is verified shipped behavior.)

## Wiring & compatibility

- **⌥⌘C keeps working.** The existing `.toggleClaudePanel` notification
  observer in `EvoRoot` calls `railManager.toggle(.claude)` instead of the old
  manager. Menu item unchanged.
- **New View menu item "Hide Panel Rail"** (title flips to "Show Panel Rail"),
  posting a new `Notification.Name.togglePanelRail` from `EvoCommands` with
  `NSApp.keyWindow`, observed in `EvoRoot` with the standard
  `note.object as? NSWindow === window` filter. Note: since `isRailVisible` is
  app-wide `@AppStorage`, the observer flips a global value; the per-window
  filter just prevents double-handling.
- **`ClaudePanelManager` is deleted**; `EvoRoot` constructs `PanelRailManager`.
  All `claudePanel` environment references migrate to `railManager`.
- `ClaudeChatManager`, `ClaudeSidePanelView` internals, and everything under
  `evo/Core/Claude/` are untouched.

## Error handling

Pure UI state; no failure paths. The single `activePanel` optional enforces
the radio invariant by construction. `SidePanel` is exhaustively switched, so
adding a case without a view is a compile error — the registry cannot drift
from the slot.

## Testing

- **Unit (Swift Testing, `evoTests/PanelRail/`):** `PanelRailManager.toggle`
  semantics — open from nil, close on same, swap on different, holder side
  derivation (`hiddenPanel.side` nil/`.secondary`), rail-visibility flag
  independence from `activePanel`.
- **Runtime (controller-driven GUI pass, same method as the walking-skeleton
  e2e):** rail renders at window edge; icon click opens the Claude panel;
  active-state highlight; click again closes; ⌥⌘C still works; draft/
  conversation still survive toggle (regression); "Hide Panel Rail" collapses
  the rail.

## Out of scope (YAGNI)

Multi-panel stacking · drag-to-reorder icons · per-panel width memory beyond
the shared holder · auto-hide/hover reveal · remappable rail shortcuts ·
badges beyond the Claude running dot · rail on the left edge.

## References

- Walking-skeleton spec (pillar decomposition, panel mechanism):
  `docs/superpowers/specs/2026-06-30-claude-browser-integration-design.md`
- Shipped mechanism this builds on: `BrowserSplitView.contentView()` nested
  `HSplit` + `SideHolder` (`evo/Features/Browser/Views/BrowserSplitView.swift:84`),
  `ClaudePanelManager` (`evo/Features/Claude/State/ClaudePanelManager.swift`,
  to be replaced), per-window notification filtering in `evo/App/EvoRoot.swift`.
