# Feature Specification: WebView Agent Tools (`webview.*` suite)

**Feature Branch**: `010-webview-agent-tools`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 009 (issue #239): surface
the plugin's agent-facing capabilities as MCP tools under the `webview`
namespace. Reshaped for the clean API: `WebviewAgentTools` builds the
suite as zuraffa-core `McpTool`s (the public runtime tier:
name/description/inputSchema/`call` → `McpToolResult`), riding the pool
(spec 006) for session continuity and the service for every operation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The tool suite (Priority: P1)

An app registers `WebviewAgentTools(service, pool).buildTools()` with its
MCP registry. The suite exposes six tools — `browse`, `execute_js`,
`read_cookies`, `screenshot`, `dismiss_dialogues`, `release_session` —
each with a name, AI-facing description, and a JSON-schema input shape.

**Why this priority**: The suite is the agent surface; everything else is
behavior of its tools.

**Independent Test**: Assert the built list (names, non-empty
descriptions, schema type objects).

**Acceptance Scenarios**:

1. **Given** `buildTools()`, **When** listed, **Then** exactly those six
   names appear with non-empty descriptions and `object`-typed schemas.

---

### User Story 2 - Browse with session continuity (Priority: P1)

An agent calls `browse {session, url}`: the url is validated (typed
failures degrade to `isError` results, never throws across the boundary),
a pooled webview is acquired for the session (domain hint from the url),
and the url loads. A following `execute_js {session, source}` acquires
the **same** pooled instance — the whole action sequence rides one
webview, keeping navigation state and cookies intact.

**Why this priority**: Session continuity is the core contract of the
tool layer (one mission, one webview).

**Acceptance Scenarios**:

1. **Given** a valid url, **When** `browse` runs, **Then** the pool
   acquired for that session+domain, the service loaded the url, and the
   result carries the `webviewId`.
2. **Given** a completed browse, **When** `execute_js` runs with the same
   session, **Then** the same `webviewId` evaluates the source and the
   result carries it.
3. **Given** an invalid url (`ftp://…`), **When** `browse` runs, **Then**
   the result is `isError` naming the typed code — no throw.
4. **Given** a missing argument, **When** the tool runs, **Then** the
   result is `isError` with a clear message — no throw.

---

### User Story 3 - Read, capture, clean, release (Priority: P2)

`read_cookies {url}` returns the cookie list (name/value/domain).
`screenshot {session}` returns an **artifact reference** plus
`byteLength` — never the byte body over the tool boundary (size
discipline, zuraffa#384). `dismiss_dialogues {session}` applies the
canonical 002 script. `release_session {session}` returns the instance to
the pool.

**Acceptance Scenarios**:

1. **Given** stored cookies, **When** `read_cookies` runs, **Then** the
   data carries them as maps.
2. **Given** a capture-capable webview, **When** `screenshot` runs,
   **Then** the result has an `artifactRef` and `byteLength`, and no byte
   array in the payload.
3. **Given** a session with overlays, **When** `dismiss_dialogues` runs,
   **Then** the canonical script was evaluated on the session's webview.
4. **Given** an active session, **When** `release_session` runs, **Then**
   the pool no longer lists it and the result is ok.

---

## Requirements

- **FR-1**: `WebviewAgentTools({service, pool})` → `buildTools(): List<McpTool>` (zuraffa core public tier), idempotent.
- **FR-2**: Six tools with the arg shapes above; every `call` validates defensively (untrusted input) and returns `McpToolResult` — never throws.
- **FR-3**: Typed `WebviewException`s degrade to `isError` results carrying code + message.
- **FR-4**: Session continuity via `WebviewPool.acquire(session, domainHint)`; `release_session` maps to `pool.release`.
- **FR-5**: `screenshot` returns `artifactRef` + `byteLength` only.

## Success Criteria

- SC-1: A mission's tool sequence operates on one webview.
- SC-2: No tool call ever throws across the MCP boundary.
- SC-3: Large payloads (screenshots) travel by reference.

## Assumptions

- Registration with a live MCP registry/stdio transport is app-side
  wiring; this package ships the tools.
- Search-engine degradation heuristics and mission-cancellation salvage
  from zikzak spec 009 ride the same seams later.
