# Feature Specification: Webview Pool — Mission-Scoped Sessions

**Feature Branch**: `006-webview-pool`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 007 (`WebViewPool` —
mission-scoped sessions, domain affinity, memory-pressure disposal; issue
#237). Agent tool sequences are stateful (browse → intercept → execute JS
→ cookies) and parallel missions otherwise leak heavyweight webview
instances. Reshaped as a pure-Dart pool over `WebviewService` with an
injectable clock (no Flutter lifecycle listener in the clean API — TTL
eviction is lazy on acquire).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Acquire and release mission-scoped sessions (Priority: P1)

An agent mission holds a session handle. Every step calls
`pool.acquire(sessionId, domainHint)` and receives the same underlying
webview id; `release(sessionId)` returns the instance to the pool as a
warm idle. Exactly one live instance per active session; ids are
pool-generated and stable for the session's lifetime.

**Why this priority**: The core contract — session-keyed instances keep
cookies/JS state consistent across a mission's steps and stop leaks.

**Independent Test**: Fake-backed service; assert instance identity and
registry counts.

**Acceptance Scenarios**:

1. **Given** no instance for session `S`, **When** `acquire(S, 'x.dev')`,
   **Then** a new headless webview is created+run and its id returned;
   `liveCount` is 1 and `sessions()` lists `S`.
2. **Given** session `S` is active, **When** `acquire(S, 'x.dev')` again,
   **Then** the same id is returned and no second instance is created.
3. **Given** session `S` is active, **When** `release(S)`, **Then** `S`
   leaves `sessions()`; the instance stays warm (idle) in the pool.

---

### User Story 2 - Domain affinity (Priority: P1)

Two sequential missions to the same site: after `release(S1)` the warm
instance still holds the site's cookies and JS state. `acquire(S2,
'x.dev')` reuses that idle instance (same underlying id, no create) when
its registrable domain matches (eTLD+1 approximation: last two host
labels). A different domain does not reuse it.

**Why this priority**: Warm reuse is the performance/state win (login
sessions survive across missions).

**Independent Test**: Release then acquire same/different domain; assert
id reuse and create counts.

**Acceptance Scenarios**:

1. **Given** an idle instance from domain `x.dev`, **When**
   `acquire(S2, 'shop.x.dev')`, **Then** the idle instance's id is
   returned (same eTLD+1) with no new create.
2. **Given** an idle instance from domain `x.dev`, **When**
   `acquire(S2, 'other.dev')`, **Then** a fresh instance is created.

---

### User Story 3 - Caps and eviction (Priority: P2)

The pool enforces `maxLive` (total held instances, platform-aware default
8) and `maxPerDomain`. On acquire past `maxLive`, idle instances are
evicted least-idle-first; when every instance is live (active), acquire
fails with the typed `pool_exhausted`. Idle instances older than `idleTtl`
(2 min default) are swept lazily on acquire (injectable clock).

**Why this priority**: iOS tolerates only a handful of live webviews;
caps + eviction are the memory-safety story.

**Independent Test**: Injected clock + small caps; assert eviction order,
typed failure, TTL sweep.

**Acceptance Scenarios**:

1. **Given** `maxLive: 2`, one idle + one active, **When** acquiring for
   a new domain, **Then** the idle instance is disposed and reused-slot
   capacity exists (create succeeds, liveCount stays ≤ 2).
2. **Given** `maxLive: 1` and one active session, **When** acquiring for
   a new session, **Then** the typed `pool_exhausted` failure is thrown.
3. **Given** an idle instance older than `idleTtl`, **When** any acquire
   runs, **Then** it is disposed by the sweep (a subsequent same-domain
   acquire creates fresh).

---

### User Story 4 - Dispose-all introspection (Priority: P2)

`disposeAll()` disposes every held instance (active and idle) and clears
the session map; `liveCount`/`sessions()` always reflect the real registry
state (assertable against the backing service).

**Why this priority**: Mission teardown / app shutdown needs a single
leak-free call.

**Acceptance Scenarios**:

1. **Given** any pool state, **When** `disposeAll()`, **Then** every held
   instance is disposed via the service and `liveCount` is 0.

---

## Requirements

- **FR-1**: `WebviewPool(service, {settings, maxLive=8, maxPerDomain=2, idleTtl=2min, clock})`.
- **FR-2**: `acquire(sessionId, {domainHint})` → pool-generated webview id; session-keyed identity; create+run on first acquire.
- **FR-3**: `release(sessionId)` → warm idle; `disposeAll()`; `liveCount`; `sessions()`.
- **FR-4**: Domain affinity by eTLD+1 approximation (last two labels) across idle instances; IP literals (IPv4/IPv6) map to themselves.
- **FR-5**: `maxLive` with LRU-idle eviction; `pool_exhausted` typed failure when saturated; `idleTtl` lazy sweep.
- **FR-6**: `maxPerDomain` — a new instance is never created for a domain already at cap: an idle instance of that domain is reused by FR-4, and when every instance of that domain is live the acquire fails typed `pool_exhausted`.

## Success Criteria

- SC-1: Parallel missions never double-create for one session.
- SC-2: Same-site sequential missions reuse warm state.
- SC-3: The pool can never exceed `maxLive` held instances.
- SC-4: Teardown leaves zero instances.

## Assumptions

- eTLD+1 approximation (last two labels) ignores multi-part TLDs
  (co.uk) — acceptable for the zuraffa scraping targets; refinement is a
  follow-up behind the same method.
- Memory-pressure listeners (Flutter lifecycle) defer to the app shell;
  the pool exposes the lazy sweep instead.
