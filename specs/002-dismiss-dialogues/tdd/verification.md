# TDD Verification — 002 dismiss-dialogues

**Verdict: PASS**

Audited from cold context against the tdd-profile, spec.md, and the working
tree at branch `002-dismiss-dialogues`.

## Test-first evidence

- `cycle-log.md` records the RED run (compile failure naming the missing
  `dismissDialogues` API) before implementation, and the GREEN run
  (`+27` app package, 51/51 repo-wide) after. The test file's behaviors map
  1:1 to spec acceptance scenarios D1–D10.

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 default off, serialized | D1 |
| US1-2 opted-in serialized | D2 |
| US2-1 one canonical evaluation on right id | D7 |
| US2-2 script removes fixed/sticky + resets overflow/margin | D3, D4 |
| US2-3 `not_created` for unknown id | D8 |
| US2-4 JS errors swallowed | D9 (+ in-script try/catch) |
| US3-1 attempts drive retries | D10 |
| US3-2 default single attempt | D6, D7 |
| FR-6 top-level only | D5 |

## Smells check

- No logic in tests beyond arrangement/action/assert; fake port is local and
  stateful only where needed. ✓
- No shared mutable fixtures across groups (`setUp` rebuilds). ✓
- Implementation contains no test-aware branches. ✓

## Mutants (reasoned)

- Flip default `dismissDialogues` to true → D1 fails. Killed. ✓
- Remove the attempts clamp → D6 (`attempts: 0`) fails. Killed. ✓
- Remove the `on Exception` swallow → D9 fails. Killed. ✓
- Drop the `not_created` guard → D8 fails (fake port would accept any id).
  Killed. ✓
- Remove the sticky branch in the script source → D3 fails (the shipped
  source is golden-pinned, so any edit is caught). Killed. ✓
- Remove the `documentElement`/`body` exclusion from the sweep → D3 fails
  (same golden pin). Killed. ✓

## Gaps (non-blocking)

- D10 asserts retry count, not elapsed delay timing — asserting wall-clock
  timing would be flaky; the delay wiring is visible in the implementation
  and exercised by D10's policy path.
- In-browser execution of the canonical script is a native/browser
  milestone (no JS runtime in this repo's VM tests) — D3/D4 pin the shipped
  source against a whitespace-normalized golden copy (D3 the whole script,
  D4 the reset block) and D5 pins the negative frame-recursion contract,
  matching the spec's Dart-side scope.

## Review delta (PR #1)

The verdict above was re-checked against the tree after the PR #1 review
fixes (cycle-log "Cycle 2"): the script gained the
`documentElement`/`body` exclusion and the collect-then-remove pass, D3/D4
became golden pins instead of marker checks, and `tasks.md` behavior refs
were aligned with `tdd/test-list.md`. Coverage table, smells, and mutants
above still hold; the mutation check was re-run against the new golden pin.
Verdict unchanged: **PASS**.
