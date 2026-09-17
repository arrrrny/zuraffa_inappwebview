# Implementation Plan: Dismiss Dialogues — Clean-Capture Overlay Removal

**Branch**: `002-dismiss-dialogues` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

Add the zikzak dialogue-dismissal feature to the clean API as three pieces:
a typed `WebviewSettings.dismissDialogues` flag riding the channel envelope,
a canonical pure-Dart `DialogueDismissScript` (removes top-level
fixed/sticky elements + resets overflow/margin), and a best-effort
`WebviewService.dismissDialogues(id, policy)` facade op with a retry policy
for late-loading overlays.

## Technical Context

**Language/Version**: Dart 3.13 (pure Dart, no Flutter runtime)
**Primary Dependencies**: none new — extends `zuraffa_inappwebview` app package only
**Storage**: N/A
**Testing**: `dart test` (VM), fake-port recording pattern per house style
**Target Platform**: all (Dart core; native apply is a later native milestone)
**Project Type**: federated plugin (app-facing package)
**Constraints**: dismissal must never propagate errors; script must not recurse into iframes

## Constitution Check

- Library-first: the script + policy are self-contained pure-Dart values in
  the app package. ✓
- Test-first: behavior list below is driven red → green before wiring. ✓

## Project Structure

### Documentation (this feature)

```text
specs/002-dismiss-dialogues/
├── spec.md          # this feature's specification
├── plan.md          # this file
├── tasks.md         # dependency-ordered task list
└── tdd/
    ├── test-list.md # behavior list (from tdd.plan)
    ├── cycle-log.md # red→green evidence
    └── verification.md  # audit verdict
```

### Code (packages/zuraffa_inappwebview)

```text
lib/src/
├── webview_types.dart       # + dismissDialogues setting (FR-1)
├── dialogue_dismiss.dart    # NEW: DialogueDismissScript, DialogueDismissPolicy (FR-2, FR-7)
├── webview_service.dart     # + dismissDialogues() facade op (FR-3..FR-5)
└── zuraffa_inappwebview.dart (barrel export)
test/
└── dialogue_dismiss_test.dart  # behavior tests (fake port)
```

## Architecture / Data Model

| Entity | Shape | Channel args |
|---|---|---|
| `WebviewSettings.dismissDialogues` | `bool`, default `false` | `dismissDialogues: bool` (always present) |
| `DialogueDismissScript` | `const` class, `source` getter | n/a (JS payload, not args) |
| `DialogueDismissPolicy` | `attempts: int` (min 1, default 1), `delay: Duration` (default 0) | n/a |

The canonical script: query all elements in `document`, read computed
`position`, remove `fixed`/`sticky` ones, then reset `overflow`/`margin` on
`documentElement` and `body`. Guarded by try/catch inside the script and
never touches `window.frames` (FR-6).

## contracts/

The port contract gains no new method: dismissal rides the existing
`evaluateJavascript` port op. The channel-envelope settings map gains the
`dismissDialogues` key — adapters forward settings verbatim, so no adapter
change is required (verified by existing adapter passthrough tests).

## MVP Definition

Stories 1 + 2 (typed setting + service op with single attempt) are the MVP.
Story 3 (retry policy) is P2 and lands in the same cycle but after MVP
behaviors are green.

## Failures & Risks

- JS errors mid-script → swallowed at service level (FR-5) and inside the
  script itself.
- Future navigation-event spec (004) will add auto-apply on load; this spec's
  facade op is the stable seam for it.
