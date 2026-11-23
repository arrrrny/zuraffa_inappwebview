# Cycle Log — 004 navigation-tracking

## Baseline

Branch `004-navigation-tracking` stacked on `003-screenshot-pdf-export`.
Baseline: 69/69 green.

## Cycle 1 — RED → GREEN

**RED**: `test/navigation_tracking_test.dart` (N1–N6) written first →
compile failure `Type 'WebviewNavigationEvent' not found` (designed red).
Adapter N7 groups appended after → same missing-API red in all three.

**GREEN**:
- NEW `navigation_tracking.dart`: `WebviewNavigationPhase`,
  `WebviewNavigationEvent` (+ `fromChannelArgs` codec), `UrlVisit`,
  `NavigationTracker` (attach/detach/handleEvent/entries/lastUrl/hasCycle,
  dedup window 500ms default, mainFrameOnly default true, injectable clock).
- `webview_port.dart` + `webview_service.dart`: `navigationEvents(id)`
  stream op, `not_created` guard, unwired `port_not_wired`.
- platform: `ChannelEventSource` typedef.
- adapters ×3: `eventSource` on the channel (optional, forwarded by
  register re-wrap), `navigationEvents` = source → non-map guard
  (`malformed_response`) → id filter → codec.

**Mid-loop fixes the tests caught (real bugs, logged honestly):**
1. Tracker dedup originally keyed off the *event* timestamp — events built
   by the codec carry `DateTime.now()`, so the injected clock was ignored
   and the dedup window mis-fired. Fixed: the tracker's clock is the
   timing authority (platform timestamps are informational).
2. N5 test originally omitted `isMainFrame: false` (asserted a drop that
   the event never declared) — test fixed, not the code.
3. Adapter stream tests: sync controllers leaked the malformed error
   synchronously out of `events.add` (unhandled in the zone); switched to
   async controllers. `emitsThrough` treats stream errors as failures, so
   the malformed case asserts `emitsError` on a first-event error. The
   group teardown awaited `close()` on a never-listened controller (never
   delivers done) → 30s timeout; teardown is now fire-and-forget.

`dart test` → 13 · 13 · 13 · 6 · 42 = **87/87 green**, analyze clean.

## Spec clarifications recorded (not edited in place)

- Dedup collapses a repeated *transition* (phase + url) within the window —
  a start/complete pair for the same url are distinct transitions and both
  survive (a url-only rule would erase completions).


## Review follow-up (PR #3 review findings)

Applied after the automated review of PR #3. The added tests were written
alongside the fixes rather than driven red-first in the loop above — noted
for honesty; the red→green evidence above is unchanged.

- **Codec hazards closed (N1).** An unrecognized `type` used to decode as
  `started` via `orElse`, injecting phantom transitions into the record;
  `fromChannelArgs` now returns null for it (the adapters skip the null) and
  raises a typed `malformed_response` for wrong-typed `url`/`isMainFrame`/
  `code` instead of leaking a `TypeError`.
- **Adapter decode (N7).** Map payloads are now filtered by id *before* their
  keys are decoded, so a payload bound for another webview can no longer
  error every subscription on the shared channel; non-map payloads keep the
  typed `malformed_response` (FR-4). Two adapter tests per platform cover
  the new split.
- **Tracker cleanup (N8).** `clear(id)` drops one record and `dispose()`
  drops every record and cancels every subscription — `_entries` previously
  only ever grew.
- The `UnwiredWebviewPort` sync-throw for `navigationEvents` is now
  documented as deliberate (FR-2) rather than left as an unexplained
  asymmetry with the adapters' `channel_not_wired` `Stream.error`.
- Spec/tasks/test-list wording aligned (FR-1/FR-3/FR-4, N1/N7 rows, counts).

Verified after the change: repo-wide 98/98 green (47 app + 6 platform +
15 × 3 adapters) and `dart analyze` clean in all five packages.
