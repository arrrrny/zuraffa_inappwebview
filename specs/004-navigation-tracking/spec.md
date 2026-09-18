# Feature Specification: Navigation Tracking

**Feature Branch**: `004-navigation-tracking`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview`'s `NavigationTracker` /
`UrlCycleEntry` (SPLIT_MAP module tier, `NavigationTrackerPort`): a unified,
ordered URL-cycle record per webview with a dedup window and main-frame
filtering. Reshaped for the clean API as (a) a typed navigation **event
stream** port op — the repo's first streaming seam — and (b) a pure-Dart
`NavigationTracker` that works without a webview. The zikzak
`keepNavigationInWebView` guard is widget-tier policy and defers to the
attachable-widget spec (FEATURES.md tier C).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Typed navigation events (Priority: P1)

A caller subscribes to `service.navigationEvents(id: 'scraper')` and
receives typed `WebviewNavigationEvent`s as the platform reports them:
phase `started`/`completed`/`failed`, url, main-frame flag, optional error
code, timestamp. The events decode from channel args
(`{'type', 'url', 'isMainFrame', 'code'}`); unknown ids fail the typed
`not_created` guard; the unwired port surfaces `port_not_wired`.

**Why this priority**: The stream is the seam every downstream feature
(recipes, VCR, auto-dismiss) consumes.

**Independent Test**: Fake port with a broadcast stream controller; assert
codec round-trip and guards.

**Acceptance Scenarios**:

1. **Given** channel args `{'type': 'completed', 'url': 'https://x.dev/',
   'isMainFrame': true}`, **When** decoded, **Then** the typed event has
   phase completed, that url, main-frame true, no error code.
2. **Given** args with `type: 'failed'` and `code: 'net_err'`, **When**
   decoded, **Then** the event carries `errorCode: 'net_err'`.
3. **Given** an id that was never created, **When** subscribing, **Then**
   the typed `not_created` failure is thrown.
4. **Given** the unwired port, **When** subscribing, **Then**
   `port_not_wired` surfaces.

---

### User Story 2 - The tracker (Priority: P1)

A caller constructs `NavigationTracker()` and either feeds it events
directly (`handleEvent`) or attaches it to a webview's event stream
(`attach(id, stream)`). The tracker keeps an ordered, deduplicated record
per webview id: the same url observed inside the dedup window (500ms
default) collapses to one entry keeping the earliest; sub-frame events are
dropped by default (`mainFrameOnly`). Cycle detection reports A→B→A
revisits — the fingerprint zikzak used to detect redirect/login loops.

**Why this priority**: The ordered URL-cycle record is the feature's value
(scrapers decide "where did I actually land" and "am I looping").

**Independent Test**: Feed synthetic events with an injected clock; assert
ordering, dedup, main-frame filter, and cycle flag.

**Acceptance Scenarios**:

1. **Given** started+completed for `https://x.dev/`, **When** recorded,
   **Then** `entries(id)` shows both visits in order and `lastUrl(id)` is
   `https://x.dev/`.
2. **Given** the same url completing twice within the dedup window,
   **When** recorded, **Then** exactly one entry is kept (earliest).
3. **Given** `isMainFrame: false` events and default settings, **When**
   recorded, **Then** they are dropped.
4. **Given** completions A → B → A, **When** recorded, **Then**
   `hasCycle(id)` is true; for A → B → C it is false.
5. **Given** an attached tracker, **When** `detach(id)` is called, **Then**
   the subscription cancels and recording stops.

---

### User Story 3 - Adapter event mapping (Priority: P2)

Each adapter (android/ios/macos) exposes `navigationEvents(id)` from an
injected event source (`channel.eventSource`, a `Stream<Object?>`
per method): raw maps decode via the typed codec, events for other ids are
filtered out, non-map payloads surface the adapter's typed
`malformed_response`, and a missing event source surfaces the typed
`channel_not_wired` failure.

**Why this priority**: Pins the native contract for the streaming seam.

**Independent Test**: Scripted stream controllers per adapter.

**Acceptance Scenarios**:

1. **Given** an event source emitting `{'id': 'w', 'type': 'started',
   'url': 'u'}` and a foreign-id event, **When** subscribed for `w`,
   **Then** only the `w` event arrives, decoded.
2. **Given** an event source emitting a non-map, **When** subscribed,
   **Then** the stream errors with the adapter's typed
   `malformed_response`.
3. **Given** no event source injected, **When** subscribing, **Then** the
   stream errors with the typed `channel_not_wired`.

---

## Requirements

- **FR-1**: `WebviewNavigationEvent` (phase/url/isMainFrame/errorCode/at) with `fromChannelArgs` codec (`type` key maps to phase).
- **FR-2**: `WebviewPort.navigationEvents({required id})` → `Stream<WebviewNavigationEvent>`; service passthrough with the `not_created` guard; unwired → `port_not_wired`.
- **FR-3**: `NavigationTracker` — `attach`/`detach`/`handleEvent`/`entries`/`lastUrl`/`hasCycle`; dedup window 500ms default (injectable clock); `mainFrameOnly` default true.
- **FR-4**: Adapter channels accept an optional `eventSource`; `navigationEvents` filters by id, decodes typed, `malformed_response` on non-map, `channel_not_wired` when absent; register forwards `eventSource` when re-wrapping for timeout.
- **FR-5**: Platform package exports the `ChannelEventSource` typedef.

### Key Entities

| Entity | Kind | Channel shape |
|---|---|---|
| `WebviewNavigationPhase` | enum | `'started' / 'completed' / 'failed'` |
| `WebviewNavigationEvent` | value object | `{'type','url','isMainFrame','code'}` |
| `ChannelEventSource` | typedef (platform pkg) | `Stream<Object?> Function(String method)` |
| `UrlVisit` | value object (tracker record) | n/a |

## Success Criteria

- SC-1: One subscription yields the ordered navigation truth for a webview.
- SC-2: Duplicate/sub-frame noise never pollutes the record.
- SC-3: Cycles (loops) are detectable from the record alone.
- SC-4: The streaming contract is identical across adapters.

## Assumptions

- Native event push is the native milestone; the Dart contract is pinned
  here (method `navigationEvents`, payload shape above).
- Widget-tier navigation guards (keepNavigationInWebView) defer to the
  attachable-widget spec.
