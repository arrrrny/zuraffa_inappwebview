# Test List — 008 vcr-record-replay

| ID | Behavior | Task | Status |
|---|---|---|---|
| V1 | recorder produces ordered entries (url/html/cookies); captures attach to their navigation; a capture delivered *inside* a freeze window attaches to the next navigation (single-flight queue, no timing crutch) | T001 | DONE |
| V2 | cassette JSON round-trip preserves entries and the capture `at` instant; recorded captures are defensively redacted; an unsupported `formatVersion` is refused with `vcr_unsupported_format` | T002 | DONE |
| V3 | exact-match serving via loadHtml (html + baseUrl) | T003 | DONE |
| V4 | path-prefix best-match fallback (query-insensitive, prefix must end on a path-segment boundary, same origin includes the port) | T004 | DONE |
| V5 | strict vcr_unmatched naming url; soft mode no-op | T005 | DONE |
| V6 | synthesized captures on the broadcast stream, in order; `dispose()` closes the stream | T006 | DONE |
| V7 | loadHtml adapter contract (method + 3 args) ×3 | T007 | DONE |

Counts: 7 behaviors, 7 driven red → green, 0 remaining.

## Revision (2026-09-18, review follow-up)

- V1: the recorded race was fixed in production, not test-side.
  `VcrRecorder.ingestNavigation` snapshots and clears the pending captures
  synchronously with the navigation event and freezes single-flight, so an
  entry cannot absorb (and then clear) a capture that belongs to the next
  navigation, and entry order follows event order. The regression test parks
  `getHtml` on a `Completer` instead of leaning on `Future.delayed`.
- V2: `at` now rides the cassette JSON (the replayer used to re-stamp a
  replayed capture with wall-clock time); `Cassette.fromJson` validates
  `formatVersion`.
- V4: matching used to ignore the path-segment boundary (`/a` served `/abc`)
  and the port (`:9999` served the `:8443` entry).
- V6: the broadcast controller had no `close()`, so awaiting completion hung;
  `VcrReplayer.dispose()` now closes it.
