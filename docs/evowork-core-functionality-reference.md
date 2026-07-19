# EvoWork core functionality reference

## Purpose and source

This document is the rebuild reference for functionality that must move from
EvoWork/OpenWork into Evo Browser before the Electron application is retired.
It was captured from the current repository at:

`/Users/mk7751/Development/evowork`

The original detailed inventory supplied on 2026-07-18 remains the canonical
line-level audit. This checked-in reference records its architectural contract,
source locations, invariants, and migration risks in a form that can guide Evo
Browser implementation work.

Engine identities:

- OpenCode: `opencode` (current default)
- Claude Code: `claude-code`
- Pinned OpenCode version: `v1.17.3` in `/constants.json`

## 1. Architecture

### Electron shell

Primary source: `apps/desktop/electron/main.mjs`.

The Electron main process owns the application lifecycle, window state,
runtime children, native filesystem dialogs, update flow, terminals, embedded
browser panel, Microsoft 365 bridge, task metadata, Windsurf sidecar, and
non-loopback fetch bridge. `preload.mjs` exposes typed renderer bridges rather
than giving the React renderer direct Node access.

Important IPC domains:

- `openwork:desktop`: workspace, engine, server, configuration, skills,
  diagnostics, reset, and filesystem commands.
- `openwork:claude`: per-session Claude lifecycle and event streaming.
- `openwork:windsurf`: token and sidecar lifecycle.
- `openwork:ms365`: authentication and Graph proxy.
- `openwork:tasks`: task metadata persistence.
- `openwork:terminal`: PTY lifecycle and streams.
- `openwork:browser`: embedded-browser tabs and navigation.
- `openwork:system`, `openwork:shell`, `openwork:migration`, and
  `openwork:updater`: native platform services.

### Runtime manager

Primary source: `apps/desktop/electron/runtime.mjs`.

Independent state machines track the selected engine, embedded OpenWork
server, optional orchestrator, Windsurf proxy, and per-session Claude child
processes.

Runtime modes:

1. Direct: spawn `opencode serve`, discover bundled or PATH binaries, generate
   credentials, and poll `/health`.
2. Orchestrator: spawn `openwork-orchestrator` with explicit daemon/OpenCode
   ports and wait up to 180 seconds for health.
3. Embedded server: start `apps/server/dist/embedded.js`, manage or reuse an
   OpenCode process, retain workspace tokens, and register bundled MCP servers.

Load-bearing behavior:

- A healthy runtime for the same workspace is reused.
- Restart first stops all runtime children and cleans packaged sidecars.
- Sticky ports and per-workspace tokens survive restarts.
- Child environments merge the user environment and enriched PATH.
- Development runtime isolation may rewrite HOME/XDG, but Claude must use the
  real user home so its credentials and session files remain available.

### Renderer and embedded server

Primary renderer sources:

- `apps/app/src/react-app/server-provider.tsx`
- `apps/app/src/react-app/global-sdk-provider.tsx`
- `apps/app/src/react-app/lib/desktop.ts`

The renderer uses React Context for runtime services, Zustand for local state,
and TanStack Query for server state. It creates an authenticated OpenCode SDK
client, subscribes to the server event stream, and polls health. Non-loopback
requests can traverse the Electron fetch bridge; loopback uses native fetch.

Primary server source: `apps/server/src/embedded.ts`.

The embedded server owns workspace/token registration, optional managed
OpenCode startup, runtime configuration, REST routes, and SSE events. Replacing
OpenCode requires replacing this server and SDK surface, not merely swapping a
model provider.

### Engine abstraction

Both OpenCode and Claude runtimes are available. OpenCode is a managed daemon;
Claude is spawned per session; Windsurf is a separately managed proxy. The
session's provider determines routing at creation time.

Migration rule: preserve the existing “gate, don't rip” architecture until a
replacement implements every server, registry, event, and persistence
responsibility currently supplied by OpenCode/OpenWork.

## 2. Claude Code engine

Primary sources:

- `apps/desktop/electron/claude/spawn-claude.mjs`
- `apps/desktop/electron/claude/translate-to-opencode.mjs`
- `apps/desktop/electron/claude/sessions.mjs`
- `apps/desktop/electron/claude/protocol-parser.mjs`
- `apps/desktop/electron/claude/*-mcp-config.mjs`

### Process contract

The real `claude` CLI is launched with stream-JSON input/output, partial
messages, verbose output, stdio permission prompts, a session UUID, selected
model/effort, MCP configuration, and a turn-specific system prompt.

Claude's environment removes conflicting Claude/Node variables and points HOME
and USERPROFILE at the real user home. Session identity is fixed at creation:
the OpenWork UUID is also Claude's UUID and transcript filename. Existing files
use `--resume`; new IDs use `--session-id`.

### Protocol translation

The line-oriented translator emits the OpenCode-compatible message and part
model used by the renderer:

- text and reasoning declarations before deltas;
- stable tool part IDs from running through completion/error;
- normalized tool names and camel-cased inputs;
- context usage, cost, tokens, rate-limit state, completion, and idle events;
- blocking permission and `AskUserQuestion` requests resolved through control
  responses.

Tool mappings include Bash, Edit/MultiEdit, Write, Read, Grep, LS, questions,
and renamed `mcp__*` tools. Edit/Write previews synthesize unified diffs.

### Session storage

Claude transcripts live under
`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`. Listing and transcript
parsing skip sidechains and rebuild tool-use/tool-result relationships. Fork
and revert operations must preserve complete turn boundaries so resumed
sessions never contain dangling tool calls.

Claude IDs are bare UUIDs; OpenCode IDs use `ses_*`. The existing routing layer
uses an explicit local session-engine binding with ID-shape fallback.

### Bundled MCP servers

The browser MCP and Microsoft 365 MCP are bundled self-contained Node ESM
artifacts and injected through Claude's `--mcp-config`. Evo Browser should
replace Electron-specific control channels, but preserve the tool protocol and
per-session injection behavior.

## 3. Copilot and Windsurf

### GitHub Copilot

Copilot is an OpenCode provider and uses its built-in GitHub device-flow OAuth
and provider-auth store. There is no custom EvoWork OAuth implementation.

Corporate-network invariant: GitHub and Copilot domains must bypass the devlab
proxy. Without the NO_PROXY rules, long-idle device-code polling is silently
dropped and authentication wedges. Preserve direct routing for GitHub login,
API, and Copilot API domains.

The provider exposes the subscription-backed model catalog returned by
OpenCode/models.dev. Model choice determines the per-session engine route.

### Windsurf

Primary sources include `runtime.mjs`, `windsurf/token-store.mjs`,
`windsurf/paths.mjs`, `windsurf/env.mjs`, `windsurf/provider-block.mjs`, and the
renderer Windsurf settings store/card.

Windsurf is a managed Node sidecar using the user's opaque Devin/Codeium token.
It exposes an authenticated OpenAI-compatible loopback endpoint, discovers
models, and registers a `windsurf` provider block in OpenCode configuration.

Required lifecycle behavior:

- secure token storage in production;
- restart after changing a token while running;
- readiness polling against `/v1/models`;
- crash detection and stderr tail reporting;
- provider-block insertion/removal;
- SIGTERM followed by SIGKILL fallback and cleanup on quit.

## 4. Microsoft 365 MCP

Primary sources:

- `packages/openwork-ms365-mcp/core.mjs`
- `packages/openwork-ms365-mcp/index.mjs`
- `apps/desktop/electron/ms365-auth.mjs`
- `apps/desktop/electron/ui-control-server.mjs`

### Authentication contract

The current single-tenant integration uses Microsoft Office first-party client
credentials and `.default offline_access` through device code. `.default` is
mandatory because explicit scopes produce AADSTS65002 for this arrangement.

Access tokens are cached in memory. The rotating refresh token is encrypted at
rest and remains in the main process. MCP requests short-lived Graph tokens
from an authenticated loopback token broker.

Presence requires redeeming the same family refresh token through a second
Office FOCI sibling client. Presence write is not available. Refresh-token
rotation is family-wide and must always persist the newest token.

### Tool catalog

- Mail: list/search/read/send/reply/reply-all/forward, drafts, folders, move,
  flag, and read state.
- Calendar: calendar view, calendars, schedules, meeting suggestions, create,
  update, respond, and cancel.
- Teams: chats, messages, teams, channels, replies, and outbound messages.
- To Do: lists, list/create/update/complete/delete tasks.
- Files and Excel: search, recordings, text read, meeting recap, tables, range
  read, and range write.
- People and presence: people search, user/manager lookup, presence, and
  connection status.

Confirmation is required for destructive operations and operations that send
content to other people. Recordings and transcripts are OneDrive files rather
than OnlineMeeting API resources. Pagination cursors are complete Graph URLs;
binary detection, OData escaping, URL encoding, and Excel workbook-session
headers must remain compatible.

## 5. Task, session, and workspace management

### Sidebar/session metadata

Primary sources:

- `domains/session/sidebar/session-management-store.ts`
- `domains/session/sidebar/app-sidebar.tsx`
- `domains/session/sidebar/app-sidebar-provider.tsx`

The persisted sidebar model includes pinned sessions, manual workspace order,
groups and assignments, collapsed groups, archived sessions/timestamps, and
Claude title overrides. The UI includes branches, drag reordering and grouping,
archive/delete/export actions, and idle/thinking/responding/error/compacting/
waiting state.

### Retention, activity, and commands

`apps/app/src/app/lib/session-retention.ts` implements global and per-workspace
auto-archive days while protecting active, busy, and already archived
sessions. Waiting badges aggregate permission and question requests through
session, group, and workspace rows.

The shell provides command palette, fuzzy session search, terminal toggle, and
new-task shortcuts. Palette modes include sessions, agents, accessible items,
settings, documentation, and feedback.

### Workspaces and session merge

`shell/use-workspace-route-state.ts` loads workspace sessions in the background
from Claude and OpenCode, unions by ID, sorts by creation time, applies local
metadata, and preserves locally created sessions for a short grace period.
Workspace/session selection and ordering are restored from local persistence;
Home is prioritized on cold start.

Composer drafts are scoped by workspace/session and bounded to 100 entries.
Multi-workspace state distinguishes home, local, and remote workspaces.

### Task-sync agent

The background Claude task agent gathers Microsoft Graph signals, correlates
email/meetings/Teams activity to open tasks, and returns structured tag,
artifact, and status proposals. The renderer applies results through the task
metadata store and invalidates task queries.

## Persistence inventory

Data that needs an explicit migration strategy:

- session pins, order, groups, assignments, collapse state, archives, and title
  overrides;
- active workspace, last session per workspace, workspace order and sort;
- per-session composer drafts;
- global and workspace retention preferences;
- per-session engine binding;
- OpenCode server/workspace/token configuration;
- Windsurf and Microsoft 365 encrypted credentials;
- task metadata, tags, artifacts, and task-sync state;
- Claude transcripts in `~/.claude/projects`.

## Native Evo Browser implementation guidance

- Put process supervision, secrets, token brokering, and filesystem access in
  the Chromium browser process or a narrowly scoped native service.
- Use Evo WebUI for session/task surfaces and Mojo for typed browser/WebUI
  boundaries; do not recreate unrestricted Electron preload bridges.
- Keep one provider-independent session/event contract.
- Reuse the existing MCP packages where possible, replacing only their
  Electron transport and credential broker.
- Preserve crash isolation: provider, MCP, and engine failures must not crash
  the browser.
- Build migration and rollback before declaring feature parity.
