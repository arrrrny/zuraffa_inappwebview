# TDD Verification — 005 network-capture

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED compile failures (`Type 'WebviewCaptureEntry'
not found` for C1a–C6; the missing `setCaptureEnabled`/`captureEvents`
surface in the adapter C7a/b/c groups ×3) and the GREEN totals at the time
(108/108 repo-wide). Two mid-loop fixes were behavior-level (URL marker
encoding, test stream isolation) — assertions were not weakened. Four
hardening cases (C3b, C4c, C5b, C5c) were appended in the fixes round;
`network_capture_test.dart` re-runs 13/13 green on this tree.

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 codec full shape | C1a |
| US1-2 enable + filter args | C1b, C2a, C7a/b/c |
| US1-3 not_created | C2a, C2b |
| US1-4 port_not_wired | C2b |
| US2-1 ordered buffer + clear | C3a |
| US2-2 maxEntries keeps latest | C5a |
| US2-3 maxBodyBytes truncates | C5a, C5c |
| US3-1 header redaction | C4a |
| US3-2 url param redaction | C4a |
| US3-3 redaction off | C4b |
| US4-1 decode + id filter | C7a/b/c |
| US4-2 malformed | C7a/b/c |
| US4-3 channel_not_wired | C7a/b/c |
| FR-1 entry + filter codec | C1a, C1b |
| FR-1 filter matching | C6 |
| FR-2 guards + unwired | C2a, C2b |
| FR-3 manager + budgets | C3a, C3b, C5a, C5b, C5c |
| FR-4 redactor at ingest | C4a, C4b, C4c |
| FR-5 adapter mapping | C7a/b/c |

## Mutants (reasoned)

- Disable redaction default → C4a fails. Killed. ✓
- Budget eviction keeps earliest instead of latest → C5a fails. Killed. ✓
- No body truncation → C5a/C5c fail. Killed. ✓
- Remove the id filter in the adapter → C7a/b/c see the foreign event. Killed. ✓
- Redact all headers → C4a's surviving `Accept: json` fails. Killed. ✓

## Gaps (non-blocking)

- Form-body param redaction (zikzak `_redactFormBody`) defers until
  bodies carry urlencoded forms in practice; the seam
  (`CaptureSecretRedactor`) is public and extensible.
- The JS injector + native push are the native milestone.
