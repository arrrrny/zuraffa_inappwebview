# Feature Specification: zuraffa_inappwebview MVP

**Template Version**: `zuraffa-migrate-1.0`
**Replaces**: `zikzak_inappwebview` (successor repo, clean git history and a
clean, fresh API — nothing inherited)

## Overview / Mission

A zuraffa-native federated webview plugin: app-facing package (Port +
Service + UseCases + Module), shared channel-envelope core, and
android/ios/macos adapters over **injected** transports. The API is shaped
by what the zuraffa ecosystem actually does with a webview (headless
scraping, cookie/session work, JS evaluation) — it deliberately does not
inherit the flutter_inappwebview-derived surface.

## User Scenarios & Testing

### User Story 1 (P1): Headless lifecycle without a platform

`WebviewService` owns the headless registry: create → run → dispose with
typed lifecycle failures (`already_created`, `not_created`,
`already_running`) before any platform call.

### User Story 2 (P1): Typed, validated inputs

`WebviewUri` accepts only http/https/about:blank. `WebviewSettings` and
`WebviewCookie` carry explicit channel args (round-trip pinned).

### User Story 3 (P1): Adapter transparency

Platform adapters map every operation to envelope method calls and decode
typed payloads; native errors surface as the adapter's typed exception with
stable codes.

### User Story 4 (P2): Zuraffa auto-DI

`WebviewModule`/`registerWebview` contribute the service + usecases;
a pre-registered `WebviewPort` (adapter or fake) is never overridden; the
unwired default surfaces `port_not_wired` typed failures.

## Requirements

- FR-1: `WebviewPort` is pure Dart; no flutter/channel imports.
- FR-2: cookies are a global shared store (no id scoping) — matching
  platform cookie semantics.
- FR-3: every port operation has a stable method name in the channel
  contract (see adapter port doc comment).

## External Dependencies & Contracts

| Dependency | Contract | Fake |
|---|---|---|
| Platform channel per OS | `ChannelInvoke` via `PlatformWebviewEnvelope` | scripted invoke maps in adapter tests |

## Lanes

- CORE: everything in this MVP (pure Dart + envelope).
- SKIN: none (headless-first; the attachable widget is a later spec).
