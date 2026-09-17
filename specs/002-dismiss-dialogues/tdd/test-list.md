# Test List — 002 dismiss-dialogues

Behaviors derived from spec.md acceptance scenarios + plan.md. All in
`packages/zuraffa_inappwebview` (fake-port pattern, no platform needed).

| ID | Behavior | Task | Status |
|---|---|---|---|
| D1 | `WebviewSettings().toChannelArgs()['dismissDialogues'] == false` (default off) | T001 | DONE |
| D2 | `dismissDialogues: true` serializes as `true` in channel args | T001 | DONE |
| D3 | canonical script removes `position: fixed`/`sticky` elements (source contains computed-position filter + removal) | T002 | DONE |
| D4 | canonical script resets `overflow`/`margin` on `documentElement` + `body` | T002 | DONE |
| D5 | canonical script touches only the top-level document (no iframe/frames recursion) | T002 | DONE |
| D6 | `DialogueDismissPolicy` clamps attempts to ≥ 1; defaults: 1 attempt, zero delay | T003 | DONE |
| D7 | `service.dismissDialogues(id)` sends exactly one `evaluateJavascript` with the canonical source | T004 | DONE |
| D8 | unknown id → typed `not_created` failure | T004 | DONE |
| D9 | port raising during dismissal is swallowed (completes normally) | T004 | DONE |
| D10 | policy `attempts: 3` → three evaluations (with delay between) | T005 | DONE |

Counts: 10 behaviors — 10 driven red → green, 0 remaining.

Script-content behaviors (D3–D5) are asserted on the shipped JS source
string: pure-Dart, deterministic, no JS runtime needed.
