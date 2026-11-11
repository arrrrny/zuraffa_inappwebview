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

## Cycle 2 — review fixes (PR #4 findings)

11 inline findings from the automated review of PR #4 (2 🟠 / 4 🟡 / 5 🔵);
every one was verified against head before fixing.

**RED**: the new regression tests fail on head — C8 (a malformed
percent-encoding in a query key throws out of `ingest`), C9/N9 (`attach`
leaks an unhandled async stream error), C10 (`maxBodyBytes` counts UTF-16
code units: `'a😀b'` survives a 4-"byte" budget whole), C11 (`x-api-key`,
`session_id` survive), S7 (`quality: 0` ships to the platform), plus the
adapter groups (`[for (final b in raw) b as int]` throws a raw `TypeError`
and copies a `List<int>` payload; a foreign payload is decoded before the
id filter).

**GREEN**:
- `CaptureSecretRedactor.redactUrl` falls back to the raw query key on
  `FormatException`/`ArgumentError` — page-controlled urls must not crash
  ingest.
- `NetworkCaptureManager.attach` / `NavigationTracker.attach` subscribe
  with `onError` (contained; debug-printed under `assert`).
- `maxBodyBytes` is real UTF-8 bytes: `_truncateUtf8` backs off to a
  character boundary, so a cut never produces a lone surrogate / U+FFFD.
- Secret carriers widened (4 headers, 6 params).
- Adapters ×3 filter raw payloads by `id` **before** decoding, so a
  foreign or unconvertible payload cannot error another webview's
  subscription; a non-map payload still surfaces the typed
  `malformed_response` (US4-2).
- Adapters ×3 `_decodeBytes` returns a `List<int>` as-is (no multi-MB copy)
  and raises the typed `malformed_response` for non-int elements.
- `ScreenshotConfiguration.quality` clamps to 1–100; an unknown navigation
  `type` decodes to the new `WebviewNavigationPhase.unknown` instead of
  `started`; `NavigationTracker.clear(id)` drops the per-id record.
- D3–D5 in `dialogue_dismiss_test.dart` are marked contract-pinning;
  behavioral coverage of the script needs a JS engine (native/e2e tier).

`dart test` → 59 · 21 · 21 · 21 · 6 = **128/128 green**, analyze clean
(the 108 baseline + 20 review-driven regression tests). This round also
fills `tasks.md` + `tdd/test-list.md` (both were committed empty) and
aligns `spec.md` with the fixed semantics.

## Deferred (recorded, not spec'd away)

Distillation (Sightings), streaming early-return, salvage flush, and
per-domain budget keying ride these seams as follow-ups (spec
Assumptions).
