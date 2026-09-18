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
| US1-2 enable + filter args | C2, C7a |
| US1-3 not_created | C2 |
| US1-4 port_not_wired | C2, C7c |
| US2-1 ordered + clear | C3 |
| US2-2 maxEntries keeps latest | C5 |
| US2-3 maxBodyBytes truncates | C5 |
| US3-1 header redaction | C4 |
| US3-2 url param redaction | C4 |
| US3-3 redaction off | C4 |
| US4-1 decode + id filter | C7b |
| US4-2 malformed | C7c |
| US4-3 channel_not_wired | C7c |
| FR-1 filter rides the enable call (matching is the platform's) | C1, C7a |

## Review follow-up (2026-09-18)

- `WebviewCaptureFilter.matches` was dead production code — nothing in
  `lib/` called it and the spec only asks the filter to ride the enable
  call — so the predicate and its test (formerly C6) are removed; the
  platform owns matching.
- `redactUrl` dropped a `#fragment` trailing a redacted param; C4 now
  asserts whole-string equality with the secret last and a fragment present.
- `maxBodyBytes` counted UTF-16 code units and could emit a lone surrogate;
  it now measures UTF-8 bytes and stops on a rune boundary, pinned by C5.
- `WebviewCaptureEntry.fromChannelArgs` reads `at` back, so a cassette
  round-trip no longer re-stamps a replayed capture with wall-clock time.

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
