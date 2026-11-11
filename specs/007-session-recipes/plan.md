# Implementation Plan: Session Recipes

**Branch**: `007-session-recipes` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

Pure-Dart record/replay: `RecipeRecorder` (spec-004 events + explicit taps
→ ordered `RecipeStep`s → `SessionRecipe`), a `replay()` free function
driving any `RecipeDriver` with progress + captured failures
(`ReplayResult`), and `WebviewServiceRecipeDriver` (loadUrl via
`WebviewUri`, canonical click script). No port widening.

## Project Structure

```text
app: lib/src/session_recipes.dart    # NEW
     test/session_recipes_test.dart  # recording fake driver + fake port
```

## Model

| Piece | Shape |
|---|---|
| `RecipeStep` | sealed: `RecipeUrlStep(url)` / `RecipeTapStep(selector)` |
| recorder | attach/detach/handleEvent/recordTap/finish; only completed main-frame visits |
| replay | sequential drive, onProgress(stepIndex,total), failures → failedStep+error |
| driver | `loadUrl(Uri)` + `tap(selector)`; service impl rides existing ops |

## MVP

US1+US2 (record + replay semantics); US3 (service driver) same cycle.
