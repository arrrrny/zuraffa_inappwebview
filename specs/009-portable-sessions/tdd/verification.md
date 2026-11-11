# TDD Verification — 009 portable-sessions

**Verdict: PASS**

## Test-first evidence

cycle-log.md records the RED run (types not found) and GREEN totals.

The review-fix cycle (2026-09-18) was driven red first: the new
behaviours below were run against the pre-fix head (`f99f0b9`) and fail
there — 9 in the core package (PS5 ×2, PS6, PS4's added assertion, C4,
C5 ×2, N1, R7) and 1 in each adapter (the non-integer byte element).

## Acceptance-criteria coverage

| Spec scenario | Covered by |
|---|---|
| US1-1 save snapshots cookies + localStorage | PS1 |
| US1-2 canonical JSON read | PS1, PS6 (a non-JSON read fails typed) |
| US2-1 load re-applies both | PS2 |
| US2-2 session_not_found, nothing applied | PS3 |
| US3-1 delete + list via store | PS4 |
| US3-2 JSON round-trip | PS4 |
| FR-5 no private format | PS1/PS4 (store is the only path) |

## Mutants (reasoned)

- Apply cookies before the not-found check → PS3 fails. Killed. ✓
- Skip localStorage read on save → PS1 fails. Killed. ✓
- Drop `savedAtMs` from `toJson` → PS4 fails: the round-tripped
  `savedAt` must equal the fixed `1700000000000` the session was built
  with. Killed. ✓ — *corrected*: this was previously credited to "PS1's
  savedAt assertion", which reads the object being **saved**, never a
  round-trip, so PS1 alone never killed it.
- Hand-roll the `setItem` escaping instead of `jsonEncode` → PS5 fails:
  it pins the generated source to the `jsonEncode`-built literal and
  recovers a hostile value by decoding it back as data. Killed. ✓ —
  *corrected*: previously ◐, on the theory that the gap was a
  quote-bearing value. A quote-bearing value is the one input a
  `'`-only escaper handles correctly; backslashes, newlines and a
  hostile `\');…;//` payload are what break it.
- Default an unknown navigation phase to `started` → the N1
  malformed-response assertion fails. Killed. ✓

## Gaps (non-blocking)

- The zuraffa session package's own `WebviewSessionStore` implementation
  lands with that package's integration.
