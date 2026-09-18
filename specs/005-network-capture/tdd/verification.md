# TDD Verification — 005 network-capture

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED compile failures and the GREEN totals
(108/108). Two mid-loop fixes were behavior-level (URL marker encoding,
test stream isolation) — assertions were not weakened.

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 codec full shape | C1 |
| US1-2 enable + filter args | C2, C7a/b/c |
| US1-3 not_created | C2 |
| US1-4 port_not_wired | C2, C7a/b/c |
| US2-1 ordered + clear | C3 |
| US2-2 maxEntries keeps latest | C5 |
| US2-3 maxBodyBytes truncates | C5 |
| US3-1 header redaction | C4 |
| US3-2 url param redaction | C4 |
| US3-3 redaction off | C4 |
| US4-1 decode + id filter | C7a/b/c |
| US4-2 malformed | C7a/b/c |
| US4-3 channel_not_wired | C7a/b/c |
| FR-1 filter matching | C6 |

## Mutants (reasoned)

- Disable redaction default → C4 fails. Killed. ✓
- Budget eviction keeps earliest instead of latest → C5 fails. Killed. ✓
- No body truncation → C5 fails. Killed. ✓
- Remove id filter in adapter → C7 sees the foreign event. Killed. ✓
- Redact all headers → C4's surviving `Accept: json` fails. Killed. ✓

## Gaps (non-blocking)

- Form-body param redaction (zikzak `_redactFormBody`) defers until
  bodies carry urlencoded forms in practice; the seam
  (`CaptureSecretRedactor`) is public and extensible.
- The JS injector + native push are the native milestone.

## Review-fix round (PR #4 findings)

| Finding (thread) | Verdict | Covered by |
|---|---|---|
| `network_capture.dart:143` redactor throws on malformed percent-encoding | applied | C8 |
| `network_capture.dart:167` / `navigation_tracking.dart:98` `attach` without `onError` | applied | C9, N9 |
| `network_capture.dart:188` `maxBodyBytes` counts code units, splits surrogates | applied (true UTF-8 bytes) | C10 |
| `network_capture.dart:95` redaction sets miss common carriers | applied | C11 |
| adapters ×3 decode before the id filter | applied (filter raw payloads first) | C7/N8 ×3 |
| adapters ×3 `_decodeBytes` raw `TypeError` + payload copy | applied | S6 ×3 |
| `network_capture.dart:59` `matches` has no production call site | documented as a consumer utility | — |
| `navigation_tracking.dart:36` unknown `type` becomes `started` | applied (`unknown` phase) | N8 |
| `navigation_tracking.dart:94` unbounded per-id record | applied (`clear(id)`) | N8 |
| `webview_types.dart:110` `quality` unvalidated | applied (clamped 1–100) | S7 |
| `dialogue_dismiss_test.dart:147` D3–D5 keyword pinning | documented as contract-pinning | — |
| `specs/005/tasks.md` + `tdd/test-list.md` committed empty | applied | T020 |

Tests: 108 → 128 (20 review-driven regression tests); every new test was
verified to fail on the pre-fix head. Analyze clean across all five
packages.
