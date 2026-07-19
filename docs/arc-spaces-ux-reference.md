# Arc Spaces UX — behavioral reference for the Evo (Chromium) rebuild

## §0 Context

### Purpose

This document specifies the **observable behavior** of Arc's "Spaces" experience so the Evo (Chromium) implementation can rebuild it. It is written as user stories with acceptance criteria. It deliberately contains **no implementation guidance** — no mention of Chromium profiles, tab groups, bookmark nodes, prefs, or C++/views structure. Describe *what the user sees and does*; the implementing agent decides *how*.

Where a requirement maps onto an existing `evo/BACKLOG.md` line, that line is cited so this spec slots onto the backlog rather than reinventing it.

### Source of truth

1. **Live Arc data** captured from Sam's daily-driver Arc via the arc-bridge tools (`list_spaces`). This is authoritative for the *data model*: every Space has a title, an optional bound profile, a folder count, and a set of saved/pinned tab URLs. Observed Space→profile bindings at capture time: `Personal → Default`, `Image Gen → Profile 2`, `Perch → Profile 3`, `TUA → Profile 1`, `TSL/AAO/DSM → Default`.
2. **Three screenshots** from Sam's Arc:
   - *Image 1* — the Spaces **overview** (all Spaces shown side-by-side as columns), each column headed by the Space name and a **profile badge** ("Default", "Perch", "TUA", …), with a per-column edit (pencil) affordance.
   - *Image 2* — the **space switcher rail** at the bottom of the sidebar: a horizontal row of Space icons plus a `+` to create a new Space.
   - *Image 3* — a single Space's sidebar flyout: a grid of **favorite tiles** at the top, and the per-Space **pinned list** ("bookmark bar") beneath the Space name.
3. **General knowledge of Arc's behavior** for details the JSON does not expose (tile pinning, auto-reset, folder nesting, editing flows). These are labeled as **Arc behavior notes** and are the softest part of the spec — verify against a live Arc if a detail is load-bearing.

### Scope

Four slices, all in scope:

- **Slice A — Per-Space profile binding** (Image 1 badges). `evo/BACKLOG.md`: "Per-Space profiles, themes, and optional cookie isolation."
- **Slice B — Space switcher rail + Space overview** (Images 1 & 2). `evo/BACKLOG.md`: "Space creation, persistent bottom selectors" (done), "Validate and tune physical trackpad Space switching", "Space rename, icon, color, reorder, and deletion controls", "Drag tabs between Spaces without exposing Chromium tab-group UI."
- **Slice C — Favorites tiles** (Image 3 top). `evo/BACKLOG.md`: "Shared Favorites section distinct from Space-local pinned tabs."
- **Slice D — Bookmark bar / folders + Space editing** (Image 3 list + pencil). `evo/BACKLOG.md`: "Folders and nested sidebar organization" and the rename/icon/color/delete controls above.

### Non-goals

Out of scope for this document (either already built, owned elsewhere, or deliberately excluded):

- The vertical sidebar shell itself, split view, and the AI entry point — already `[x]` in the backlog.
- Tab auto-archiving policy tuning, Media/Downloads/Easels/Boosts/Archived-Tabs surfaces (the left rail in Image 1) — separate features. The "Today"/ephemeral tab *zone* is described only as context in §6.
- Sync of Spaces across devices.
- Any Chromium-internal mechanism. If you catch yourself writing "profile" or "tab group," you've left this document's remit.

### Arc-primary, with Ora notes

Everything is grounded in the live Arc behavior above. Where Ora (the Chromium-based Arc successor) is known to diverge, it appears as an **Ora divergence** call-out. Ora could not be inspected live; treat Ora notes as leads to verify, not settled requirements. Whenever Arc and Ora disagree on a user-facing default, the choice is surfaced in **§7 Open decisions** rather than silently picked.

---

## §1 Domain model & vocabulary

The implementing agent must use these terms consistently. Ambiguity here causes the most rework.

- **Space** — a named, themed workspace inside a single browser window. Has a title, an icon (emoji or symbol), a color/gradient theme, an optional bound profile, an ordered list of pinned items (tabs and folders), and a set of currently-open tabs. Switching Spaces swaps the sidebar contents and the window's accent theme. Multiple Spaces coexist in one window; exactly one is *active* at a time.
- **Profile binding** — the association between a Space and a browsing identity ("Default" or a named profile). Determines which cookies, logins, and extensions a Space's tabs use. Several Spaces may share one profile. Shown as the **profile badge** next to the Space name.
- **Favorites** — a row/grid of **icon-only tiles** pinned at the very top of the sidebar. In Arc these are **global**: the same favorites appear at the top of *every* Space. Meant for the handful of sites used constantly (mail, calendar, chat). See §4 and the §7 open decision on scope.
- **Pinned tabs** (a.k.a. the "bookmark bar" in Sam's words) — the **per-Space** ordered list beneath the Space name. Persistent, Space-local, survives closing the tab. Can be grouped into folders. This is what most of Image 1's columns show.
- **Folder** — a named, collapsible container for pinned items within a Space's pinned list. Folders may nest. Per-Space.
- **Today / ephemeral tabs** — non-pinned open tabs, shown below the pinned list, that auto-archive after an inactivity interval. Included here only so the sidebar's three zones (favorites → pinned → today) are unambiguous; policy is out of scope (§6).
- **Space switcher rail** — the horizontal strip of Space icons + `+` at the bottom of the sidebar (Image 2). The primary point-and-click way to change the active Space.
- **Space overview** — the zoomed-out view (Image 1) showing all Spaces as parallel columns for cross-Space organization: reordering Spaces, dragging tabs between Spaces, and per-Space editing.

**Sidebar zone order (top → bottom):** Favorites tiles → active Space's pinned list (with folders) → active Space's Today/ephemeral tabs → Space switcher rail.

---

## §2 Slice A — Per-Space profile binding

*(Image 1 profile badges — `Personal → Default`, `Perch → Perch/Profile 3`, `TUA → TUA/Profile 1`, …)*

### Narrative

Each Space can be bound to a distinct browsing identity so that logins, cookies, and extension state don't bleed across contexts. A Space bound to a "Perch" identity stays logged into Perch's tooling; a Space bound to "TUA" stays logged into TUA's. Multiple Spaces may share one identity (several of Sam's Spaces share "Default"). The binding is visible at a glance via a badge on the Space, and the currently-active identity is unmistakable while browsing.

### User stories

**A1 — Bind a Space to a profile.**
As a user, I want to assign a Space to a specific browsing identity, so that its tabs use that identity's logins and cookies without affecting my other Spaces.
- Acceptance:
  - When editing a Space (§5), I can choose its bound identity from the set of available identities, or leave it on the default identity.
  - Changing a Space's identity takes effect for tabs opened afterward; the change is persisted and survives restart.
  - A Space always has exactly one bound identity (never zero, never many). The default identity is the fallback.

**A2 — See which identity a Space uses.**
As a user, I want each Space to display its bound-identity badge, so that I never confuse which context I'm acting in.
- Acceptance:
  - The Space's badge shows the identity's name (e.g. "Default", "Perch", "TUA") next to the Space title in the overview (Image 1) and in the Space header when active.
  - The badge is legible against the Space's color theme in both light and dark appearance.
  - While a Space is active, its identity is discoverable without opening any menu.

**A3 — Share one identity across Spaces.**
As a user, I want multiple Spaces to be able to use the same identity, so that related Spaces share logins while staying organizationally separate.
- Acceptance:
  - Two or more Spaces may be bound to the same identity simultaneously; their pinned lists, themes, and tabs remain independent.
  - Cookies/logins are shared *only* among Spaces bound to the same identity.

**A4 — Isolation guarantee.**
As a user, I want tabs in Spaces bound to different identities to be isolated, so that signing into an account in one Space does not sign me in elsewhere.
- Acceptance:
  - A login performed in a Space bound to identity X is present in other Spaces bound to X and absent from Spaces bound to a different identity.
  - Isolation holds for cookies and site logins at minimum. (Whether extension state and history are also partitioned is an **open decision** — see §7.)

### Arc behavior notes

- Arc surfaces the binding as a small pill/badge beside the Space name; the identity name is short (often the org name). The live data confirms the mapping is one-profile-per-Space with sharing allowed.

### Ora divergence

- Ora also binds Spaces to profiles and is generally more explicit about it in its Space-creation flow. Worth checking Ora's create-Space wizard for a cleaner "pick an identity" step than Arc's edit-after-the-fact model.

### Open decision → §7

- Depth of isolation (cookies only vs. cookies + extensions + history), and whether identity is chosen at Space-creation time or only via later editing.

---

## §3 Slice B — Space switcher rail + Space overview

*(Image 2 bottom rail; Image 1 overview)*

### Narrative

Users move between Spaces constantly, so switching must be instant and available several ways: a click on the bottom rail, a trackpad swipe, and a keyboard shortcut. Separately, when reorganizing, users zoom out to an **overview** where all Spaces sit side-by-side as columns — there they reorder Spaces, drag tabs from one Space into another, and jump into per-Space editing. Backlog status: the rail and Space creation are done `[x]`; trackpad switching, reorder/rename/etc., and cross-Space tab dragging are open.

### User stories

**B1 — Switch Spaces from the rail.**
As a user, I want a persistent row of Space icons at the bottom of the sidebar, so that I can jump to any Space in one click.
- Acceptance:
  - The rail shows one icon per Space, in the user's Space order, plus a trailing `+` to create a Space.
  - The active Space's icon is visually distinguished from the rest.
  - Clicking an icon makes that Space active: the sidebar contents and window theme switch immediately; the previously active Space's open tabs are preserved.
  - The rail is always visible while the sidebar is open (it does not scroll away with the pinned list).

**B2 — Create a Space.**
As a user, I want to add a new Space from the rail, so that I can spin up a new context quickly.
- Acceptance:
  - Activating `+` creates a Space and makes it active.
  - The new Space starts with a default (or user-chosen) name, icon, color, and identity, and an empty pinned list.
  - The new Space's icon appears in the rail immediately and persists across restart.

**B3 — Switch Spaces by swipe.**
As a user, I want to swipe horizontally on the trackpad over the sidebar/content to move to the adjacent Space, so that switching feels physical.
- Acceptance:
  - A horizontal two-finger swipe advances to the next/previous Space in rail order.
  - Switching stops at the ends (no wrap) — *or wraps* — this is an **open decision** (§7); pick one and be consistent.
  - The gesture is distinguishable from in-page horizontal scroll (e.g. requires the gesture to originate over the sidebar, or a threshold). Backlog: "Validate and tune physical trackpad Space switching."

**B4 — Switch Spaces by keyboard.**
As a user, I want keyboard shortcuts to change Spaces, so that I can switch without the mouse.
- Acceptance:
  - There is a shortcut to go to the next and previous Space, and/or to jump to the Nth Space by number.
  - Shortcuts move the active Space and update sidebar + theme identically to a rail click.
  - (Exact key assignments are an **open decision**, §7 — align with Arc's or with Evo's existing shortcut map.)

**B5 — Open the Space overview.**
As a user, I want to zoom out to see all my Spaces at once as columns, so that I can reorganize across Spaces.
- Acceptance:
  - There is an affordance to enter the overview (Image 1) showing every Space as a column headed by its name, icon, and profile badge, listing that Space's pinned items.
  - From the overview I can select a Space to enter it.
  - The overview reflects live Space state (adding/removing/renaming a Space updates it).

**B6 — Reorder Spaces.**
As a user, I want to change the order of my Spaces, so that my most-used Spaces sit where I expect.
- Acceptance:
  - I can drag a Space to a new position (in the overview and/or via the rail).
  - The new order is reflected in the rail, the overview, and swipe/keyboard traversal order, and persists across restart. Backlog: "Space … reorder … controls."

**B7 — Drag tabs between Spaces.**
As a user, I want to drag a tab from one Space's column into another in the overview, so that I can move work to the right context.
- Acceptance:
  - Dragging a pinned tab from Space A's column and dropping it into Space B's column moves (or copies — decide, §7) it into B's pinned list at the drop position.
  - The moved tab adopts Space B's context on next load (see identity note below).
  - No raw tab-group/other Chromium chrome is exposed during the drag. Backlog: "Drag tabs between Spaces without exposing Chromium tab-group UI."
  - **Interaction with Slice A:** if A and B use different identities, moving a tab changes which identity loads it. The spec's stance: **moving a tab re-homes it to the destination Space's identity** (i.e. context follows the Space, not the tab). Flag if this causes a surprising re-login; this is called out in §7.

### Arc behavior notes

- In the overview, each column has a move/drag handle and a "…" overflow menu (bottom corners in Image 1); the pencil per column enters editing (§5).
- Arc's swipe switching is continuous/animated (the theme cross-fades). Match the *behavior* (adjacent-Space traversal, theme change) even if the animation differs.

### Ora divergence

- Ora exposes Space switching similarly (bottom rail + shortcuts). Confirm Ora's swipe threshold and whether Ora wraps at the ends — it's a good tie-breaker for the §7 wrap decision.

### Open decision → §7

- Swipe wrap vs. clamp; exact keyboard assignments; tab drag = move vs. copy; whether reorder is available from the rail directly or only in the overview.

---

## §4 Slice C — Favorites tiles

*(Image 3 top grid of icon-only tiles)*

### Narrative

Favorites are the sites a user touches all day. They live as compact **icon-only tiles** at the very top of the sidebar, above everything else, and — in Arc — they are **global**: the same tiles appear at the top of every Space. A favorite tile always points at its pinned site; opening it reuses/refreshes that site rather than accumulating duplicates.

### User stories

**C1 — Pin a site as a favorite.**
As a user, I want to pin a site to the favorites row, so that it's one click away everywhere.
- Acceptance:
  - I can pin the current tab (or a pinned tab) to favorites.
  - The favorite renders as an icon-only tile (site favicon/icon), no title text, in the top grid.
  - The favorite persists across restart.

**C2 — Favorites are shared across Spaces.**
As a user, I want my favorites to appear in every Space, so that my core tools are always reachable regardless of which Space I'm in.
- Acceptance:
  - The same favorites row renders at the top of the sidebar in every Space. *(This is the Arc default and the backlog intent: "Shared Favorites section distinct from Space-local pinned tabs." If §7 chooses per-Space favorites instead, this criterion changes.)*
  - Favorites are visually distinct from the per-Space pinned list below them (tiles vs. titled rows).

**C3 — Open a favorite without duplicating it.**
As a user, I want clicking a favorite to go to that site, so that I don't spawn endless duplicate tabs of the same site.
- Acceptance:
  - Activating a favorite opens/focuses that site. If it's already open in the current Space, focus it rather than opening a second copy. (Match Arc's single-instance feel.)
  - A favorite that has been navigated away from returns to its pinned URL when re-activated (favorites don't "drift" to wherever you last browsed). See Arc behavior note.

**C4 — Reorder and unpin favorites.**
As a user, I want to rearrange and remove favorites, so that the row stays curated.
- Acceptance:
  - I can drag favorites to reorder them within the grid; order persists.
  - I can unpin a favorite; it's removed from the row in all Spaces.

### Arc behavior notes

- Arc "pinned favorites" **auto-reset**: navigating within a favorite's tab and then leaving it returns the tile to its canonical URL, and Arc tends to keep a single live instance per favorite. Replicate this "always-fresh, single-instance" feel; the exact reset trigger (on blur, on Space switch, on timer) is a detail to tune.
- Favorites show **no text label**, only the icon — this is what visually separates the top grid (Image 3) from the titled pinned list beneath it.

### Ora divergence

- Ora is reported to treat pinned/favorite tabs more per-Space than globally. This is exactly the tension in the §7 open decision; Ora is the counter-example to Arc's global model.

### Open decision → §7

- **Global vs. per-Space favorites.** Arc = global; Ora leans per-Space; the backlog says "shared." Recommend defaulting to **global/shared** (matches backlog + Arc) and consider a later per-Space override. Decide before building.

---

## §5 Slice D — Bookmark bar / folders + Space editing

*(Image 3 pinned list under the Space name; Image 1 per-column pencil)*

### Narrative

Beneath the favorites row, each Space has its own persistent, ordered list of **pinned tabs** — Sam's "bookmark bar." Related pins group into **folders** (Image 1 shows folders like "Health", "Financial", "DOCS/TOOLS", "PROD", "DEV"), which can nest. This list is Space-local: the pins in "Perch" are unrelated to those in "TUA." Separately, each Space is **editable** — name, icon, color theme, bound identity (§2) — and **deletable**. Backlog: "Folders and nested sidebar organization" and "Space rename, icon, color, reorder, and deletion controls."

### User stories — pinned list & folders

**D1 — Pin a tab into the current Space.**
As a user, I want to pin a tab so it stays in this Space's list, so that I don't lose it when the tab closes or auto-archives.
- Acceptance:
  - Pinning adds the tab as a titled row in the active Space's pinned list and persists it across restart.
  - Pinned rows show the site's title (and icon), distinguishing them from the icon-only favorites above.
  - A pin belongs to exactly one Space (the active one) unless explicitly moved (§3 B7).

**D2 — Reorder pinned items.**
As a user, I want to drag pinned tabs and folders to reorder them, so that the list reflects my priorities.
- Acceptance:
  - I can drag a pin or folder to a new position within the Space; order persists.

**D3 — Group pins into folders.**
As a user, I want to put pins into named folders, so that a busy Space stays organized.
- Acceptance:
  - I can create a folder, name it, and move pins into it.
  - A folder can be expanded/collapsed; collapse state persists.
  - Folders may nest (a folder inside a folder), matching Image 1's structure.
  - Deleting a folder prompts for what happens to its contents (move out vs. delete) — pick a defined behavior (§7).

**D4 — Remove a pin.**
As a user, I want to unpin/delete a pinned item, so that stale entries don't accumulate.
- Acceptance:
  - Unpinning removes the row from the Space's list; the underlying tab (if open) either stays open as an ephemeral tab or closes — pick one defined behavior and apply it consistently.

### User stories — Space editing

**D5 — Rename a Space.**
As a user, I want to rename a Space, so that its label matches its purpose.
- Acceptance:
  - I can edit the Space title (e.g. via the per-column pencil in the overview, Image 1, and/or a context menu).
  - The new name updates the Space header, the overview column, and any labeled reference; persists across restart.

**D6 — Set a Space's icon.**
As a user, I want to pick a Space's icon, so that I recognize it instantly in the switcher rail.
- Acceptance:
  - I can choose an icon (emoji and/or symbol) for the Space.
  - The chosen icon renders in the switcher rail (Image 2), the overview column header, and the Space header; persists.

**D7 — Set a Space's color theme.**
As a user, I want to choose a Space's color/gradient, so that each Space is visually distinct and I always know where I am.
- Acceptance:
  - I can pick a color/gradient theme for the Space.
  - Activating the Space applies its theme to the sidebar/window accent (matching the tinted columns in Image 1).
  - Themes remain legible for badges, text, and tiles in light and dark appearance; persists.

**D8 — Delete a Space.**
As a user, I want to delete a Space I no longer need, so that my switcher stays clean.
- Acceptance:
  - I can delete a Space from its edit affordance/overflow menu.
  - Deletion is confirmed (destructive), and defines what happens to the Space's pinned items and open tabs (discard vs. archive — §7).
  - After deletion the Space disappears from the rail and overview; the active Space falls back to an adjacent Space; persists.

### Arc behavior notes

- The pencil per overview column (Image 1) is the primary editing entry point; a "…" overflow handles delete and less-common actions.
- Icon picking in Arc is an emoji/symbol picker; color is a themed gradient palette rather than a raw color wheel.
- Folders in Arc render as titled, collapsible rows with a folder glyph (Image 1's "Health", "PROD", etc.).

### Ora divergence

- Ora's Space editing is broadly equivalent (name/icon/color). If Ora offers a nicer single "edit Space" panel that combines identity + name + icon + color in one place, prefer that consolidated flow over Arc's split pencil/menu.

### Open decision → §7

- Folder-delete behavior; unpin's effect on the live tab; Space-delete disposition of tabs/pins.

---

## §6 Cross-cutting requirements

**Persistence.** Spaces, their order, identities, themes, icons, favorites, pinned lists, and folder structure (including collapse state) all survive quit/relaunch. Nothing in Slices A–D is session-only.

**The three sidebar zones.** Top → bottom: **Favorites** (global icon tiles, §4) → **Pinned list** (per-Space titled rows + folders, §5) → **Today/ephemeral tabs** (non-pinned open tabs that auto-archive; policy out of scope). The Space switcher rail (§3) sits below all of these and stays pinned to the bottom. Zones are visually separable so a user never confuses a global favorite with a per-Space pin.

**Empty states.** A brand-new Space (B2) shows an empty pinned list gracefully (not a broken/blank panel) and still renders favorites, the header (name/icon/badge), and the rail. An account with a single Space still shows the rail with that one icon plus `+`.

**Drag-and-drop consistency.** Dragging is used for: reordering favorites (§4 C4), reordering pins/folders (§5 D2), moving pins into folders (§5 D3), reordering Spaces (§3 B6), and moving tabs between Spaces (§3 B7). Drop targets should highlight; an invalid drop should no-op cleanly rather than lose the item.

**Theme legibility.** Every Space theme (§5 D7) must keep the profile badge (§2), favorite tiles (§4), pinned text (§5), and folder labels legible in both light and dark appearance.

**No leakage of engine chrome.** Per the backlog, none of these interactions may expose raw Chromium tab-group or profile-switcher UI to the user. The Space model is the only organizational concept the user sees.

**Keyboard & discoverability.** Core actions (switch Space, new Space, pin, new folder) should be reachable by keyboard and/or a command surface, not mouse-only. Exact bindings per §7.

---

## §7 Open decisions for Sam

These are the points where Arc, Ora, and the backlog don't fully agree, or where a behavior is destructive/surprising enough to want an explicit call. Each has a recommended default so the implementing agent isn't blocked.

1. **Favorites scope — global vs. per-Space.** Arc = global; Ora leans per-Space; backlog says "shared." *Recommend: global/shared* (matches Arc + backlog), revisit per-Space later. (§4)
2. **Profile isolation depth.** Cookies/logins only, or also extensions and history partitioned per identity? *Recommend: cookies + logins + extension state per identity; shared history* — but confirm, this shapes the whole model. (§2 A4)
3. **When identity is chosen.** At Space-creation time (Ora-style wizard) vs. only via later editing (Arc-style). *Recommend: offer it at creation and in edit.* (§2, §5)
4. **Swipe switching at the ends.** Wrap around vs. clamp. *Recommend: clamp* (less disorienting); verify against Ora. (§3 B3)
5. **Keyboard assignments.** Which keys switch Spaces / create Space / pin / new folder. *Recommend: mirror Arc's where they don't collide with Evo's existing map.* (§3, §6)
6. **Tab drag between Spaces — move vs. copy**, and the **identity re-home** on move. *Recommend: move, and re-home to the destination Space's identity* (context follows the Space); warn if it forces a re-login. (§3 B7)
7. **Unpin's effect on a live tab.** Keep it open as ephemeral vs. close it. *Recommend: keep open as ephemeral.* (§5 D4)
8. **Folder delete.** Move contents out vs. delete contents. *Recommend: prompt, default to move-out.* (§5 D3)
9. **Space delete disposition.** Discard pins/tabs vs. archive them. *Recommend: confirm + archive (recoverable).* (§5 D8)

---

## Appendix — traceability to `evo/BACKLOG.md`

| Backlog line | Covered by |
|---|---|
| Space creation, persistent bottom selectors, isolated Space tabs `[x]` | §3 B1, B2 (documents existing behavior) |
| Validate and tune physical trackpad Space switching | §3 B3 |
| Space rename, icon, color, reorder, and deletion controls | §3 B6, §5 D5–D8 |
| Drag tabs between Spaces without exposing Chromium tab-group UI | §3 B7, §6 |
| Shared Favorites section distinct from Space-local pinned tabs | §4 (all), §5 D1, §6 |
| Folders and nested sidebar organization | §5 D3 |
| Per-Space profiles, themes, and optional cookie isolation | §2 (all), §5 D7 |
