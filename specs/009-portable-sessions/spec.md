# Feature Specification: Portable Sessions

**Feature Branch**: `009-portable-sessions`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 014 (`WebViewSessions`
via `zikzak_session`'s `SessionPort` — never its own storage format). A
webview authenticates once; its session (cookies + localStorage) persists
across app restarts and loads onto a fresh webview at the same site
programmatically. Reshaped for the clean API: the storage contract is the
`WebviewSessionStore` port interface (implemented by the zuraffa session
package or any store); the controller lives here.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save a session (Priority: P1)

A caller authenticates a headless webview, then calls
`sessions.save(webviewId: 'w', name: 'shop', origin: 'https://x.dev')`.
The controller snapshots the origin's cookies (via the shared cookie
store) and the webview's localStorage (via a canonical
`JSON.stringify(localStorage)` evaluation), freezes them into a
`PortableSession {name, origin, cookies, localStorage, savedAt}`, and
persists it through the injected `WebviewSessionStore` — never a private
format.

**Why this priority**: Persisting the authenticated state is the feature.

**Independent Test**: Fake store + fake port; assert the stored session's
contents and the evaluation the port received.

**Acceptance Scenarios**:

1. **Given** cookies `sid=1` for the origin and localStorage
   `{'theme': 'dark'}`, **When** `save` is called, **Then** the store
   received a session carrying both, with the name and origin pinned.
2. **Given** the webview, **When** saving, **Then** the port received a
   `JSON.stringify(localStorage)` evaluation (the canonical read).

---

### User Story 2 - Load a session (Priority: P1)

On a fresh webview at the same origin, `sessions.load(webviewId, name)`
re-applies every cookie through the cookie store and every localStorage
entry through `localStorage.setItem` evaluations. A missing name is the
typed `session_not_found` failure (no throw-to-crash, no partial apply).

**Why this priority**: Restore is what makes sessions portable.

**Acceptance Scenarios**:

1. **Given** a stored session with cookies + localStorage, **When**
   `load` is called, **Then** each cookie is re-set via the service and
   each localStorage entry is written via an `setItem` evaluation.
2. **Given** no stored session for the name, **When** `load` is called,
   **Then** the typed `session_not_found` failure surfaces and nothing
   was applied.

---

### User Story 3 - Session hygiene (Priority: P2)

`sessions.delete(name)` removes the stored session; `sessions.list()`
names the stored sessions (store-backed). The `PortableSession` payload
round-trips JSON (`toJson`/`fromJson`) with pinned name/origin/cookies/
localStorage/savedAt — the format any store implementation persists.

**Acceptance Scenarios**:

1. **Given** stored sessions, **When** `delete`/`list`, **Then** the
   store reflects the removal and the listing.
2. **Given** a session, **When** `toJson` then `fromJson`, **Then** all
   fields survive.

---

## Requirements

- **FR-1**: `PortableSession {name, origin, cookies, localStorage, savedAt}` with JSON round-trip.
- **FR-2**: `WebviewSessionStore` port: `save/read/delete/list` — the only persistence path.
- **FR-3**: `WebViewSessions` controller over `WebviewService`: `save` (cookie snapshot + canonical localStorage read), `load` (cookie re-apply + `setItem` writes), `delete`, `list`.
- **FR-4**: `session_not_found` typed failure; no partial application on failure.
- **FR-5**: No private storage format — everything goes through the store port.

## Success Criteria

- SC-1: Authenticate once, restore anywhere (same origin).
- SC-2: Missing sessions fail typed, never partially apply.
- SC-3: Any store backend works through the port.

## Assumptions

- localStorage capture is main-frame, same-origin (the webview is at the
  target origin when saving).
- Per-instance isolated data stores (zikzak issue #253) remain
  nice-to-have.
