# Evo ↔ Arc Feature Gap Analysis

_Generated 2026-06-26. Evo features verified against the codebase; Arc features web-verified._

## Context that frames everything below

- **Arc is frozen.** The Browser Company put Arc into maintenance mode (May 2025) and was acquired by Atlassian (~$610M, Oct 2025). Arc still ships and gets Chromium security fixes but **no new features** — its focus moved to the AI-first **Dia** browser. So this is a comparison against a *fixed* target, not a moving one. Evo doesn't need to chase a roadmap; it needs to close a finite, known set of gaps.
- **Evo's North Star is something Arc never had:** AI-aware browsing + MCP integration (Anthropic Swift MCP SDK) + a real AI-provider abstraction with Claude first-class. Several "gaps" below are actually places where Evo can *leapfrog* Arc, not just match it.
- **Scoring rubric.** `relevanceToEvo` weights AI/MCP-aligned and core daily-driver features **high**; explicit non-goals (ad-blocking, extensions, non-Mac platforms, public-release polish) are **skip**; iOS-dependent items are **low**.

## Scorecard

50 comparison rows (46 Arc features + 4 cross-cutting capabilities Arc lacks but that matter for Evo):

| Evo status vs Arc | Count |
|---|---|
| **Parity** (done) | 5 |
| **Partial** (works, missing a dimension) | 15 |
| **Missing** | 28 |
| **Not applicable** (intentional non-goal) | 2 |

| Relevance to Evo | Count |
|---|---|
| High | 14 |
| Medium | 20 |
| Low | 13 |
| Skip (out of scope) | 3 |

**Headline:** Evo already has the *structural* Arc experience — vertical sidebar, Spaces, pinned/favorite tabs, a Spotlight launcher, per-Space profiles, tab hibernation, a global media player. What it lacks is **(a) the entire AI layer** (Arc Max + Evo's own MCP ambitions — there is literally zero model-API code today) and **(b) a handful of signature daily-driver interactions**, chiefly **Split View** and a **recoverable tab Archive**.

---

## Where Evo is already at parity or ahead

Evo is **not** a strict subset of Arc. Things Evo has that Arc does **not**:

| Evo strength | Why it beats Arc |
|---|---|
| **Per-Space privacy controls** (per-Space tracker/fingerprint/cookie policy) | Arc has no per-Space privacy model — inherits Chromium defaults globally. |
| **Active fingerprinting protection** (canvas/WebGL/audio/hardware spoofing JS) | Arc ships no anti-fingerprinting layer at all. |
| **Native Keychain password manager** (Touch ID unlock, Space-scoped creds, generation, clipboard auto-clear) | Arc uses the Chromium store and **never syncs passwords**; Evo's vault is OS-integrated. |
| **Per-Space search engine *and* per-Space AI engine** | Arc binds Profiles to Spaces but offers no per-Space search/AI choice — and this is directly on Evo's path to a per-Space Claude default. |
| **Local-first, no mandatory account** | Arc forces signup (widely criticized); Evo keeps all state in local SwiftData. |
| **Provider-extensible launcher pipeline** | The exact abstraction seam CLAUDE.md names for the AI/MCP layer — Evo is closer to its North Star surface than a from-scratch browser would be. |
| **WKWebView + explicit tab hibernation + viable iOS path** | Lower memory than Chromium on Mac; native materials; a tractable WebKit iOS future (Arc is Chromium and abandoned). |
| **Unified global media player** (multiple background sessions, per-session volume) | Arc splits this across a video Mini Player + a separate audio widget; Evo's consolidated controller is arguably better. |

Parity (nothing to build): **Sidebar chrome**, **per-Space pinned tabs**, **Cmd+T launcher / new-tab experience**, **Ask-ChatGPT URL shortcut**, **audio/media controls**.

---

## The gaps that matter — High relevance

These are the AI/MCP-aligned and core daily-driver items. **The AI cluster all depends on one missing foundation**, so order matters.

### Cross-cutting foundations (build these first — they unblock everything else)

| Gap | Status | Effort | Notes |
|---|---|---|---|
| **AI provider abstraction + Claude API client** | Missing | Medium | **The keystone.** Verified: zero model-API code in `evo/` — the only "anthropic/openai" hits are a color name and search-engine alias strings. Unblocks 6+ AI features. This is CLAUDE.md priority #2. Needs: provider protocol, streaming Anthropic client, Keychain key storage, cancel model. |
| **MCP client integration** (Swift MCP SDK) | Missing | Large | Evo's **#1 differentiator**; no Arc analogue exists. Connect to local dev-project MCP servers, then layer agentic page interaction. Sits on top of the provider layer + launcher action registry. |
| **Reader Mode / Readability extraction** | Missing | Medium | Confirmed absent. Two wins in one: a clean reading view **and** the structured page-text primitive that Ask-on-Page, 5-Second Previews, and agentic synthesis all require. CLAUDE.md already calls out bundling Mozilla `Readability.js`. |
| **Command Bar action/command registry** | Partial | Medium | The launcher does search/nav/AI-shortcuts/history today but has **no extensible action verbs** (no "New Space", "switch Space", slash-commands). This registry is the natural host for MCP tool invocation — parity *and* differentiator in one build. |
| **`evo://` automation URL scheme** | Partial | Small | Info.plist registers only http/https. A custom scheme routed to the existing per-window NotificationCenter actions (open URL / new tab / switch Space / run AI query) is a cheap, high-leverage "act on the browser" surface for the agentic layer. **Best leverage-to-cost ratio in the whole analysis.** |

### AI features (each becomes cheap once the foundation lands)

| Arc feature | Status | Effort | Gap |
|---|---|---|---|
| **Ask on Page** (Cmd+F → AI answer over page) | Missing | Medium | Evo has the `Cmd+F` find half (mark.js, match counter); zero "Ask" half. Arc's flagship feature is **verified Claude-powered** — i.e. it *is* Evo's differentiator on the most natural surface. The find-bar seam + page-text access already exist. |
| **5-Second Previews** (AI summary on link hover) | Missing | Medium | Evo's hover preview shows only the URL string. Needs background fetch-and-extract of the unvisited target — which is also an MCP/agentic building block, so effort compounds. |
| **Browse for Me** (agentic multi-page research → cited answer) | Missing | Large | Reframe as a **desktop** feature, not a mobile clone. AI visits multiple pages, reads them, synthesizes one cited answer — the core of Evo's agentic vision. Largest, most strategic AI build. |
| **Live Folders** (auto-updating sidebar folders) | Missing | Large | **Most MCP-aligned showcase:** auto-compile live dev-tool data (GitHub PRs, Linear) into the sidebar — exactly Evo's pitch. A `Folder` SwiftData model exists but is an inert stub. Needs folder UI activation + a refresh/data-source framework that an MCP server feeds. |

### Non-AI daily-driver gaps an Arc refugee will feel

| Arc feature | Status | Effort | Gap |
|---|---|---|---|
| **Split View** (side-by-side tabs) | Missing | Large | **The top non-AI gap.** Content area renders a single `activeTab` WebView. The vendored Split library + reusable per-tab view exist, but hosting multiple live WKWebViews (focus, hibernation interplay, split-as-sidebar-entry) is substantial. Schedule *after* the AI foundation, but don't drop it. |

---

## Medium relevance

| Arc feature | Status | Effort | One-line gap |
|---|---|---|---|
| **Tab Auto-Archive / recoverable Archive ("ARChive")** | Partial→Missing | Medium | Evo's per-Space auto-close timer **destroys** tabs (last 5 in-memory) instead of moving them to a persistent, searchable Archive. Signature Arc anti-hoarding UX; timer infra already exists. |
| **Dedicated History browsing UI** | Missing | Small | History is recorded but only reachable via launcher fuzzy-search — no date-grouped browsable view. `DownloadsHistoryView` is a ready-made template to clone. (Draft missed this; it's a genuine daily-driver gap.) |
| **Air Traffic Control** (rule-based link routing to Spaces) | Missing | Medium | No URL-pattern → Space rules engine. The `.openURL` observer is the exact seam; needs a rules model + settings UI. |
| **Per-Space theming** (color/gradient sidebar tint) | Partial | Small | Evo extracts a per-*tab* color but has no user-set per-Space palette. Recognizable Arc identity cue; purely cosmetic. |
| **Global Favorites** (pinned tiles across *every* Space) | Partial | Medium | Evo's favorites are scoped per-Space; Arc's are app-wide. A "mail/calendar everywhere" tile must currently be recreated per Space. |
| **Boosts** (per-site CSS/JS theming + Zap) | Missing | Medium | No user-authored per-domain injection UI. The `WKUserScript` plumbing exists and is reusable for AI-driven page manipulation. |
| **Mini Player gestures** (manual PiP trigger) | Partial | Small | Auto-PiP-on-tab-switch already ships; missing a manual "double-right-click → PiP" trigger. Cheap to close. |
| **Tidy Tab Titles** (AI-rewrite title on pin) | Missing | Small | Single call site in `togglePinTab()` once the provider layer exists. Gate behind a toggle. |
| **Instant Links** (Shift+Enter → best result) | Missing | Medium | Needs the AI pick; the "Folder of <topic>" half is blocked on real tab folders. |
| **Tidy Tabs** (AI auto-grouping) | Missing | Large | Gated behind building the whole tab-folder feature first. |
| **Hardware media keys / Now Playing** | Missing | Small | No `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`. `MediaController` is the natural bridge. |
| **Developer Mode toolbar** | Partial | Medium | Full Web Inspector already exposed; missing the one-click console/network toolbar + auto-enable-on-localhost (a cheap, high-fit win for a dev). |
| **Calendar/email hover previews** | Missing | Large | Arc bakes in per-service OAuth. More Evo-native route: surface this via an MCP calendar/Gmail server feeding the AI layer. |
| **Folders** (sidebar grouping) | Missing | Medium | Stub model only. Unblocks Tidy Tabs + "Folder of" Instant Links, hence medium. |
| **Arc Search mobile / Browse-for-Me capability** | Missing | Large | Mobile shell = low; the *capability* (desktop) = build via provider layer (overlaps Browse for Me). |
| **Today's tabs auto-archive** | Partial | Medium | Structure matches; closes together with the recoverable Archive. |
| **Spaces (per-Space theming)** | Partial | Small | Core Spaces at parity; only theming remains. |
| **Page translation** | Missing | Medium | No `Translation` framework usage; low for a US solo dev but cheap via the native framework. |
| **Session/window state restoration** | Partial | Medium | Tabs persist (SwiftData) but window size/position/active-tab don't restore across launches. |
| **Command-line / URL scheme** | Partial | Small | Covered by the `evo://` foundation row above. |

---

## Low relevance / Skip (tracked so they aren't mistaken for gaps)

- **Low (nice-to-have, mostly downstream of an iOS port or low payoff for a solo tool):** Profiles decoupled from Spaces, Little Arc, Peek, Easels, Notes, Tidy Downloads, Arc Sync (CloudKit), Arc mobile companion, Downloads "Library 2.0" aggregation, multi-browser import wizard.
- **Skip (explicit non-goals per CLAUDE.md):**
  - **Browser extensions** — WebKit can't run Chrome Web Store extensions; Pi-hole + native dev cover the need.
  - **Mandatory account/login** — conflicts with Evo's local-first design (and is a criticized Arc anti-feature).
  - **Ad/tracker content-blocking UI** — Pi-hole at DNS; the inherited `AdBlockService` stays unused.
- **Phantom feature:** "Pinned-tab summarization" isn't a real Arc capability — a conflation of Tidy Tab Titles + 5-Second Previews. No work to do.

---

## Recommended build order

The dependency chain is the whole story: **one foundation unblocks the entire AI surface.**

1. **AI provider abstraction + Claude client** _(medium)_ — the keystone; nothing AI ships without it. CLAUDE.md priority #2.
2. **Launcher action/command registry** _(medium)_ — turns the omnibox into the host for AI/MCP commands. Parity + differentiator in one.
3. **MCP client integration** _(large)_ — the North Star; sits on top of #1 and #2.
4. **Ask on Page** _(medium)_ — Arc's flagship AI feature = Evo's differentiator on the most natural surface; highest-value first use of the provider layer.
5. **Reader Mode / Readability** _(medium)_ — shared prerequisite for #4, 5-Second Previews, and agentic synthesis; also a standalone win.
6. **Live Folders backed by MCP** _(large)_ — the flagship MCP showcase (GitHub PRs / Linear into the sidebar).
7. **Desktop Browse-for-Me** _(large)_ — agentic multi-page read + synthesized cited answer; the payoff of the MCP/provider work.
8. **`evo://` automation scheme** _(small)_ — cheap, high-leverage "act on the browser" surface for the agentic layer; can land early alongside #2.
9. **Split View** _(large)_ — the top non-AI daily-driver gap; schedule after the AI foundation but don't drop it.

**Quick wins worth slotting in opportunistically:** dedicated History view (small, clone `DownloadsHistoryView`), manual PiP trigger (small), hardware media keys (small), per-Space theming (small), auto-open-inspector-on-localhost (small/dev-fit).
