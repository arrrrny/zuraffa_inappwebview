# Feature Specification: Session Recipes — Record/Replay User Flows

**Feature Branch**: `007-session-recipes`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview`'s `session_recipe` module
(`RecipeRecorder`/`RecipeReplayer`/`ReplayDriver` + models, SPLIT_MAP
`RecipePort`). A recipe is a recorded user flow (url visits, taps) that an
agent can replay against a live webview — the guided-scraping primitive.
Reshaped as pure Dart: the recorder observes spec-004 navigation events
plus explicitly recorded taps; the replayer drives any `RecipeDriver`
(service-backed by default).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Record a flow (Priority: P1)

A caller attaches a `RecipeRecorder` to a webview's navigation events and
records taps as the agent performs them. Each completed main-frame url
visit becomes a url step; each `recordTap(selector)` becomes a tap step
carrying the selector. Steps keep recording order; `finish()` produces the
named `SessionRecipe`.

**Why this priority**: Recording is the artifact — nothing replays
without it.

**Independent Test**: Feed synthetic navigation events + taps; assert the
step sequence.

**Acceptance Scenarios**:

1. **Given** attached navigation events with completions for A then B,
   **When** `finish()` is called, **Then** the recipe has url steps
   `[A, B]` in order.
2. **Given** `recordTap('#buy')` between two url visits, **When**
   `finish()` is called, **Then** the order is url A, tap `#buy`, url B.
3. **Given** no recorded activity, **When** `finish()` is called, **Then**
   an empty recipe with the given name is produced (no throw).
4. **Given** `started` (not completed) or sub-frame events, **When**
   observed, **Then** no step is recorded.

---

### User Story 2 - Replay a flow (Priority: P1)

A caller replays a recipe through a `RecipeDriver`: each url step calls
`driver.loadUrl`, each tap step calls `driver.tap(selector)`, in order.
Progress is reported per step (`stepIndex`, `total`); success returns a
completed `ReplayResult`. A driver failure at step k produces a failed
result naming the step and carrying the error — steps before k were
already driven (honest partial progress).

**Why this priority**: Replay is the value — the same flow re-runs against
live sites for scraping/verification.

**Independent Test**: Recording fake driver; scripted failure at a step.

**Acceptance Scenarios**:

1. **Given** a recipe [url A, tap `#buy`, url B], **When** replayed,
   **Then** the driver receives `loadUrl(A)`, `tap('#buy')`,
   `loadUrl(B)` in order and the result is completed with 3/3 steps.
2. **Given** progress reporting, **When** each step starts, **Then** the
   callback sees `stepIndex` increment 0→1→2 with `total` 3.
3. **Given** the driver throws at step 2, **When** replayed, **Then** the
   result is failed with `failedStep` 2 and the original error; the first
   two steps were driven.

---

### User Story 3 - The service-backed driver (Priority: P2)

`WebviewServiceRecipeDriver` adapts the recipe vocabulary onto
`WebviewService`: `loadUrl` validates and loads via `WebviewUri`;
`tap(selector)` evaluates a canonical click script
(`document.querySelector(sel)?.click()`). Wrong ids fail typed
(`not_created` via the service).

**Why this priority**: Makes the driver real without inventing new port
surface.

**Acceptance Scenarios**:

1. **Given** a created webview, **When** `driver.loadUrl(Uri)` is called,
   **Then** `service.loadUrl` receives the validated url.
2. **Given** a created webview, **When** `driver.tap('#buy')` is called,
   **Then** the port receives an `evaluateJavascript` source that selects
   `#buy` and clicks it.

---

## Requirements

- **FR-1**: `RecipeStep` variants: url (String) and tap (selector String); `SessionRecipe {name, steps}` immutable.
- **FR-2**: `RecipeRecorder {attach, detach, recordTap, finish}` — completed main-frame visits become url steps via spec-004 events; taps explicit.
- **FR-3**: `RecipeDriver {loadUrl, tap}` interface; `replay(recipe, driver, {onProgress})` → `ReplayResult {completed, stepsDriven, failedStep?, error?}`.
- **FR-4**: `WebviewServiceRecipeDriver` over `WebviewService` (loadUrl via `WebviewUri`, canonical tap script).
- **FR-5**: Failures during replay never throw out of `replay` — they are captured in the result.

## Success Criteria

- SC-1: A recorded flow replays identically against a fresh webview.
- SC-2: Replay progress/failure is observable without exceptions.
- SC-3: The recorder ignores non-step noise.

## Assumptions

- Signal matching, cookie/session snapshots, and selector-candidate
  scoring from zikzak's full model defer behind these types (the step
  list is forward-compatible).
- Native tap interception is the native milestone; taps are recorded
  explicitly by the caller today.
