# Cycle Log — 005 network-capture

## Baseline

Branch `005-network-capture` stacked on `004-navigation-tracking`.
Baseline: 87/87 green.

## Cycle 1 — RED → GREEN

**RED**: `test/network_capture_test.dart` (C1–C6) →
`Type 'WebviewCaptureEntry' not found` (designed red). Adapter C7 groups
→ missing `setCaptureEnabled`/`captureEvents` (designed red ×3).

**GREEN**:
- NEW `network_capture.dart`: `WebviewCaptureEntry` (+codec),
  `WebviewCaptureFilter` (+`matches`), `CaptureBudget`,
  `CaptureSecretRedactor` (zikzak A15 key lists, marker `<redacted>`),
  `NetworkCaptureManager` (attach/detach/ingest/entries/clear; redaction +
  budget at ingest; maxEntries keeps latest; body truncation).
- Port/service/unwired/barrel widened with `setCaptureEnabled` +
  `captureEvents`; the four existing test fakes widened mechanically.
- Adapters ×3: `setCaptureEnabled` call (id + enabled + filter spread) and
  `captureEvents` on the 004 event-source shape.

**Mid-loop defects the tests caught:**
1. `Uri.replace(queryParameters:)` percent-encodes `<redacted>` → fixed
   with a raw-string query rebuild (decode key for comparison only, keep
   original encoding for non-secret parts).
2. The first adapter C7 test reused one derived stream chain across three
   assertions ("Stream has already been listened to") → split into three
   focused tests with fresh controllers.

`dart test` → 17 · 17 · 17 · 6 · 51 = **108/108 green**, analyze clean.

## Deferred (recorded, not spec'd away)

Distillation (Sightings), streaming early-return, salvage flush, and
per-domain budget keying ride these seams as follow-ups (spec
Assumptions).
