# Evo Browser backlog

This backlog tracks Evo-specific work layered on Chromium. Chromium upstream
maintenance is intentionally not duplicated here.

## In progress

### Arc-style browser shell

- [x] Branded Chromium application and isolated profile.
- [x] Chrome extension compatibility, including 1Password.
- [x] Vertical sidebar baseline.
- [x] Space creation, persistent bottom selectors, and isolated Space tabs.
- [x] Native split view baseline.
- [x] Page-aware Evo AI entry point.
- [ ] Validate and tune physical trackpad Space switching.
- [ ] Space rename, icon, color, reorder, and deletion controls.
- [ ] Drag tabs between Spaces without exposing Chromium tab-group UI.
- [ ] Shared Favorites section distinct from Space-local pinned tabs.
- [ ] Folders and nested sidebar organization.

### AI foundation

- [x] Detect and invoke the locally authenticated Claude Code CLI without
      blocking Chromium's browser UI thread.
- [x] Add a functional `chrome://evo-ai` conversation surface with provider
      status, prompt suggestions, loading/error states, and rendered replies.
- [x] Attach active-tab title and sanitized origin/path context while stripping
      query parameters and fragments before the context crosses the AI boundary.
- [x] Disable Claude tools and session persistence for the initial browser
      prompt adapter.
- [ ] Replace the temporary WebUI promise bridge with the provider/MCP Mojo
      service.
- [ ] Stream Claude responses and persist resumable browser AI sessions.
- [ ] Add selected text and explicitly approved page-content extraction.

## Planned epics

### EvoWork/OpenWork parity and retirement

Reimplement the load-bearing functionality from the current Electron
EvoWork/OpenWork application inside Evo Browser. EvoWork remains available
until the exit criteria below are satisfied, then it will be deprecated.

Technical reference:
[EvoWork core functionality](docs/evowork-core-functionality-reference.md).

#### 1. Runtime and engine foundation

- [ ] Define an engine-agnostic native session client and event model.
- [ ] Implement a Chromium browser-process runtime manager for managed child
      processes, health checks, restart, crash state, and shutdown.
- [ ] Port the embedded OpenWork server/workspace registry or replace every
      server and SDK responsibility it currently owns.
- [ ] Preserve per-session engine selection. Provider selection at session
      creation determines routing; changing providers creates or restarts the
      appropriate session rather than mutating an incompatible live session.
- [ ] Implement secure per-engine token storage using macOS Keychain or an
      equivalent native encrypted store.
- [ ] Add native diagnostics for engine install, doctor, start, stop, restart,
      status, logs, and version.

#### 2. OpenCode and Claude Code

- [ ] Keep OpenCode as the first load-bearing engine while parity is built.
- [ ] Preserve the pinned OpenCode version and explicit upgrade process.
- [ ] Spawn and supervise the real `claude` CLI per session using the user's
      real home directory so existing Claude credentials and transcripts work.
- [ ] Port the stream-JSON parser and OpenCode-compatible event translation:
      text, reasoning, tools, deltas, questions, permissions, usage, rate
      limits, completion, and idle state.
- [ ] Support Claude transcript listing, resume, fork, revert, and unrevert
      without producing dangling tool calls/results.
- [ ] Inject Evo Browser, runtime, and Microsoft 365 MCP configurations into
      Claude sessions.

#### 3. Subscription-backed providers

- [ ] Expose GitHub Copilot through OpenCode's provider authentication and
      model catalog.
- [ ] Preserve direct GitHub/Copilot network bypass rules required for device
      flow on the corporate network.
- [ ] Port Windsurf's managed sidecar lifecycle, secure token storage,
      OpenAI-compatible provider registration, model discovery, crash status,
      and cleanup.
- [ ] Keep provider failures isolated so one provider cannot take down the
      browser or unrelated sessions.

#### 4. Microsoft 365 MCP

- [ ] Port the existing Microsoft 365 MCP package and Graph operation catalog.
- [ ] Implement the Office FOCI device-code and refresh-token lifecycle with
      native encrypted storage.
- [ ] Preserve separate presence-token redemption through the FOCI sibling
      client and the `.default` scope constraint.
- [ ] Support mail, calendar, Teams, To Do, files, recordings/transcripts,
      Excel, people, user lookup, presence, and connection status.
- [ ] Require confirmation for outbound-to-human and destructive operations.
- [ ] Keep refresh tokens in the browser process; MCP processes receive only
      short-lived access tokens through an authenticated local broker.

#### 5. Tasks, sessions, and workspaces

- [ ] Build the task/session sidebar with pinned, grouped, archived, reordered,
      branched, waiting, and activity states.
- [ ] Add multi-workspace routing, ordering, background session loading, and
      last-session restoration.
- [ ] Merge OpenCode and Claude sessions without losing pending local sessions
      during background refresh.
- [ ] Persist composer drafts per workspace/session with bounded retention.
- [ ] Implement global and per-workspace automatic session archival.
- [ ] Add command palette, session search, terminal toggle, and new-task
      shortcuts.
- [ ] Port terminal PTY sessions into a browser-native side panel or WebUI.
- [ ] Port the background task-sync agent that correlates Microsoft 365
      activity with tasks and proposes tags, artifacts, and status changes.

#### 6. Migration and EvoWork deprecation

- [ ] Define an export format for EvoWork workspaces, session metadata,
      grouping, archives, ordering, drafts, engine bindings, and task metadata.
- [ ] Build an idempotent importer with dry-run, backup, and migration report.
- [ ] Validate existing Claude transcripts directly from `~/.claude/projects`.
- [ ] Run EvoWork and Evo Browser in parallel through a parity test period.
- [ ] Publish a deprecation notice only after the exit criteria are met.
- [ ] Keep a rollback path until migrated data and daily workflows are verified.

#### Exit criteria

EvoWork can be deprecated when all of the following are true:

- OpenCode and Claude Code can create, resume, stream, use tools, request
  permission, and recover from crashes in Evo Browser.
- Required Copilot and Windsurf subscription workflows function on the
  corporate network.
- The Microsoft 365 tool catalog used in daily work is available with correct
  confirmation gates and secure token handling.
- Workspaces, sessions, groups, archives, drafts, tasks, and relevant metadata
  migrate without loss.
- Evo Browser has passed a sustained daily-use period with no workflow that
  requires reopening EvoWork.

## Later

- [ ] Provider-independent agent orchestration over current-page context.
- [ ] Native MCP connection manager for stdio and Streamable HTTP servers.
- [ ] Per-Space profiles, themes, and optional cookie isolation.
- [ ] Browser/session data backup and restore.
