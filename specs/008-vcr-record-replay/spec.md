# Feature Specification: VCR — Deterministic Record/Replay

**Feature Branch**: `008-vcr-record-replay`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 008 (issue #238,
`CassetteEngine`): agent-driven scraping must be regression-testable in CI
without live network or real webviews. Record real traffic once
(navigations, served HTML, capture events, cookie snapshots) into a
versioned cassette; replay deterministically by serving the cassette.
Reshaped for the clean API onto the 004/005 seams plus one new port op
(`loadHtml`). Gzip container and request-normalization matching defer
(versioned JSON in, forward-compatible).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record into a versioned cassette (Priority: P1)

A caller drives a real headless session while `VcrRecorder.record(id)`
watches the webview's streams: each completed main-frame navigation
becomes a cassette entry carrying the url, the served HTML, a cookie
snapshot, and the capture entries observed since the previous navigation.
`stop()` produces a `Cassette` with a declared format version that
round-trips through JSON (`toJson`/`fromJson`).

**Why this priority**: The cassette is the CI artifact — everything else
consumes it.

**Independent Test**: Fake streams + service snapshots; assert entry
shape + JSON round-trip.

**Acceptance Scenarios**:

1. **Given** two completed navigations with html/cookie snapshots, **When**
   `stop()`, **Then** the cassette has two ordered entries with url/html/
   cookies each.
2. **Given** a cassette, **When** `toJson()` then `fromJson()`, **Then**
   the entries are identical.
3. **Given** capture events between navigations, **When** recorded,
   **Then** they attach to the entry of their navigation (not the next).
4. **Given** the format version, **When** read, **Then** it is `1`.

---

### User Story 2 - Replay deterministically, offline (Priority: P1)

In replay, `VcrReplayer.loadUrl(url)` never hits the network: an exact
cassette match serves the recorded HTML through the new `loadHtml` port op
(with the recorded url as base) and synthesizes the entry's capture
events on the replayer's `captureEvents` stream — so a
`NetworkCaptureManager` attached downstream runs unmodified.

**Why this priority**: Serving recorded content is the entire point — CI
missions run with zero network.

**Independent Test**: Cassette + fake service; assert loadHtml calls and
synthesized captures.

**Acceptance Scenarios**:

1. **Given** a cassette entry for `https://x.dev/a`, **When**
   `replayer.loadUrl('https://x.dev/a')`, **Then** the port receives
   `loadHtml` with that entry's html and the url as base.
2. **Given** the entry carries two capture events, **When** served,
   **Then** the replayer's capture stream emits both, in order.
3. **Given** no exact match but an entry with the same path prefix,
   **When** loaded, **Then** the best-match entry is served (fallback).

---

### User Story 3 - Unmatched discipline (Priority: P2)

An unmatched url in replay is a hard failure by default — the typed
`vcr_unmatched` error names the url. With `strict: false` (CI flake
triage), the load is a soft no-op returning null instead.

**Acceptance Scenarios**:

1. **Given** strict mode (default) and an unknown url, **When**
   `loadUrl`, **Then** the typed `vcr_unmatched` failure is thrown.
2. **Given** `strict: false`, **When** `loadUrl` on an unknown url,
   **Then** it completes without serving and without throwing.

---

### User Story 4 - Adapter contract for loadHtml (Priority: P2)

android/ios/macos pin the new op: method `loadHtml` with `id`, `html`,
`baseUrl` args (same envelope discipline as `loadUrl`).

**Acceptance Scenarios**:

1. **Given** a scripted channel, **When** the adapter port calls
   `loadHtml`, **Then** the method name and all three args ride the
   envelope verbatim.

---

## Requirements

- **FR-1**: `Cassette {formatVersion=1, entries}` + `CassetteEntry {url, html, cookies, captures}`; JSON round-trip.
- **FR-2**: `VcrRecorder {record(id), stop()}` over 004 events + 005 capture events + service html/cookie snapshots; secrets re-redacted defensively.
- **FR-3**: `WebviewPort.loadHtml({id, html, baseUrl})` (channel `loadHtml`), service passthrough + guard, unwired failure, adapter mapping ×3.
- **FR-4**: `VcrReplayer(cassette, service, {strict=true})` — `loadUrl` serves via `loadHtml` (exact → path-prefix best match), synthesizes captures on a broadcast stream.
- **FR-5**: `vcr_unmatched` typed failure naming the url; soft mode returns null.

## Success Criteria

- SC-1: A recorded session replays with zero network calls.
- SC-2: Downstream capture/distillation logic runs unmodified on
  synthesized events.
- SC-3: The cassette format is versioned and JSON-portable.

## Assumptions

- Gzip container, request normalization, and redaction hooks beyond the
  005 redactor defer behind the versioned format.
- `loadHtml` is the native seam the native milestone implements to
  render offline content.
