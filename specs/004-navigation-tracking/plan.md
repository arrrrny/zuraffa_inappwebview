# Implementation Plan: Navigation Tracking

**Branch**: `004-navigation-tracking` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

The repo's first streaming seam: a typed `WebviewNavigationEvent` +
`navigationEvents(id)` port stream, an optional injected
`ChannelEventSource` on the adapter channels (typedef in the platform
package), and a pure-Dart `NavigationTracker` (ordered dedup'd URL-cycle
record with cycle detection, injectable clock).

## Technical Context

Dart 3.13 · no new deps · `dart test` everywhere · streams are broadcast
from the adapters (native push), single-subscription acceptable at the
port contract level (adapters may re-listen per subscription via the
source callback).

## Project Structure

```text
platform: lib/src/platform_webview_envelope.dart   # + ChannelEventSource typedef
app:      lib/src/navigation_tracking.dart         # NEW: event, phase, UrlVisit, NavigationTracker
          lib/src/webview_port.dart                # + navigationEvents
          lib/src/webview_service.dart             # + passthrough + unwired
adapters: lib/src/<p>_webview_channel.dart         # + eventSource field
          lib/src/<p>_webview_port.dart            # + navigationEvents impl
          lib/src/register.dart                    # forward eventSource when re-wrapping
tests:    test/navigation_tracking_test.dart (app) + adapter test additions ×3
```

## Data model

| Piece | Shape |
|---|---|
| phase enum | `started / completed / failed` ← channel `type` |
| event | `phase, url, isMainFrame (default true), errorCode?, at (clock)` |
| tracker record `UrlVisit` | `url, phase, at, errorCode?` |
| dedup | a (phase + url) repeat immediately after the preceding visit within `dedupWindow` collapses into that visit; adjacency-scoped, applied per id |

Cycle rule: among a webview's recorded visits, the latest url reappearing
anywhere earlier in the record ⇒ `hasCycle == true` (consecutive repeats
included, so A → A → A reports a cycle).

## MVP Definition

US1 + US2 (typed events + tracker semantics). US3 (adapter mapping) in the
same cycle.

## Risks

- Widening the port breaks the four existing test fakes — mechanical
  additions (same as 003).
- register re-wrap must not silently drop the injected eventSource (FR-4).
