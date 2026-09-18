# Cycle Log — 007 session-recipes

## Baseline

Branch `007-session-recipes` stacked on `006-webview-pool`.
Baseline: 116/116 green.

## Cycle 1 — RED → GREEN

**RED**: `test/session_recipes_test.dart` (R1–R7) →
`Type 'RecipeDriver' not found` / `Method not found: 'RecipeRecorder'`
(designed red).

**GREEN**: NEW `session_recipes.dart`:
- sealed `RecipeStep` (`RecipeUrlStep`/`RecipeTapStep`), `SessionRecipe`
  → R1–R3
- `RecipeRecorder` (attach/detach on spec-004 events, explicit
  `recordTap`, `finish`) with completed-main-frame-only filtering → R1,
  R2, R4
- `replay(recipe, driver, {onProgress})` → sequential drive,
  `ReplayProgress(stepIndex, total)`, `ReplayResult` with captured
  `failedStep`/`error` (never throws) → R5, R6
- `WebviewServiceRecipeDriver` — `loadUrl` via validated `WebviewUri`,
  `tap` via canonical `querySelector(...).click()` script → R7

`dart test` → app **66** (+7), repo 17·17·17·6·66 = **123/123 green**,
analyze clean.

## Notes

- The tap script quotes/escapes the selector; a missing-element click is
  a no-op (`?.click()`).
  *(Post-review fix: the original `?? {click: null}` guard still threw on
  a miss, and the selector literal is now `jsonEncode`d so backslashes
  cannot emit a script that does not parse.)*
- zikzak's signal matching, selector-candidate scoring, and snapshot
  models defer behind the sealed step list (spec Assumptions).
