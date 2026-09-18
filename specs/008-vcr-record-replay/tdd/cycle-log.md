# Cycle Log — 008 vcr-record-replay

## Baseline

Branch `008-vcr-record-replay` stacked on `007-session-recipes`.
Baseline: 123/123 green.

## Cycle 1 — RED → GREEN

**RED**: `test/vcr_record_replay_test.dart` (V1–V6) →
`Method not found: 'VcrRecorder'` / `'Cassette'` (designed red). Adapter
V7 groups → missing `loadHtml` (designed red ×3).

**GREEN**:
- NEW `vcr_record_replay.dart`: `Cassette`/`CassetteEntry` (formatVersion
  1, `toJson`/`fromJson`), `VcrRecorder` (streams via `record`,
  `ingestCapture` defensively re-redacts, `ingestNavigation` snapshots
  html+cookies through the service, `stop`), `VcrReplayer` (exact →
  same-origin path-prefix longest-match; serves via `service.loadHtml`;
  synthesizes captures on a broadcast stream; `vcr_unmatched` strict
  failure / soft no-op).
- Port widening: `loadHtml({id, html, baseUrl})` — abstract op, service
  guard + unwired, adapter envelope call ×3, fakes updated.

**Mid-loop fixes the tests caught:**
1. The redaction test raced `ingestNavigation` (async snapshot) without
   awaiting — the recorder produced zero entries. Fixed the test to
   await (API surface unchanged; `ingestNavigation` is documented async).
2. A cascade-on-literal parse issue in the recorder test setup —
   rewritten as plain assignments.

`dart test` → 18 · 18 · 18 · 6 · 74 = **134/134 green**, analyze clean.

## Deferred (documented)

Gzip container, request normalization matching, per-mission cassette
stores — behind the versioned format (spec Assumptions).
