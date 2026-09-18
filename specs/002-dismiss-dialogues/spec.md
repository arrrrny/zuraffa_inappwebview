# Feature Specification: Dismiss Dialogues — Clean-Capture Overlay Removal

**Feature Branch**: `002-dismiss-dialogues`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 002 (user description:
"Add a new setting to inAppWebviewSettings called dismissDialogues set false
by default that will dismiss fixed/sticky overlays for clean captures"),
reshaped for the zuraffa clean API: a typed setting in `WebviewSettings`
plus a canonical, pure-Dart dismissal script the service can apply on a
headless webview after load.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Typed setting, default off (Priority: P1)

A developer configures a headless webview with
`WebviewSettings(dismissDialogues: true)`. The flag rides the platform
envelope like every other setting, so the native side (and the channel
contract) sees `dismissDialogues` in the settings args. With defaults, the
flag is `false` — no DOM modification ever happens unless the caller opts in.

**Why this priority**: The setting is the contract seam; every consumer
(native auto-apply, agent loops, recipes) reads it.

**Independent Test**: Assert `WebviewSettings().toChannelArgs()` omits/omits
not the key per the flag, and that the default is `false`.

**Acceptance Scenarios**:

1. **Given** default `WebviewSettings`, **When** serialized to channel args,
   **Then** `dismissDialogues` is present and `false`.
2. **Given** `WebviewSettings(dismissDialogues: true)`, **When** serialized,
   **Then** the channel args carry `dismissDialogues: true`.

---

### User Story 2 - Apply the canonical dismissal script (Priority: P1)

A scraping caller finishes `loadUrl` on a page cluttered with cookie banners,
chat widgets, and sticky navbars, then calls
`service.dismissDialogues(id: 'scraper')`. The service evaluates the
canonical built-in script in the webview: elements with computed
`position: fixed` or `position: sticky` are removed from the top-level
document, and `overflow`/`margin` are reset on `documentElement` and `body`
so captures have no scrollbar artifacts. The call is a no-op-safe typed
operation: unknown ids fail `not_created`; JavaScript errors during removal
are swallowed (they must never break the webview or the caller's flow).

**Why this priority**: This is the working dismissal behavior — the setting
alone does nothing on the Dart side.

**Independent Test**: Drive a fake port that records `evaluateJavascript`
sources; assert the shipped script is evaluated on the right id and that the
script source hides fixed/sticky elements and resets overflow/margin.

**Acceptance Scenarios**:

1. **Given** a created headless webview, **When** `dismissDialogues(id)` is
   called, **Then** the port receives one `evaluateJavascript` call whose
   source is the canonical `DialogueDismissScript.source`.
2. **Given** the canonical script, **When** inspected, **Then** it hides
   `position: fixed`/`position: sticky` elements (`display: none`, so a
   retry can still restore them), resets `documentElement`/`body` overflow
   and margin, and touches only the top-level document (no iframe
   recursion).
3. **Given** an id that was never created, **When** `dismissDialogues(id)` is
   called, **Then** it throws the typed `not_created` failure.
4. **Given** the port raises a JS evaluation error for the dismissal call,
   **When** `dismissDialogues(id)` is called, **Then** the error is swallowed
   (completes normally) — dismissal is best-effort by contract.

---

### User Story 3 - Retry window for late overlays (Priority: P2)

A page injects its cookie banner two seconds after load. The caller applies
dismissal with a `DialogueDismissPolicy(attempts: 3, delay: 250ms)`; the
service re-evaluates the script per attempt so late overlays land inside the
retry window and are removed. The default policy is a single attempt.

**Why this priority**: Real-world pages load overlays late; retries make
captures reliable, but a single attempt stays the honest default.

**Independent Test**: Fake port + fake clock or short delays; assert the
port received exactly `attempts` evaluations.

**Acceptance Scenarios**:

1. **Given** policy `attempts: 3`, **When** `dismissDialogues(id, policy)`
   completes, **Then** the port received 3 dismissal evaluations.
2. **Given** the default policy, **When** dismissal completes, **Then**
   exactly 1 evaluation was sent.

---

## Requirements

### Functional Requirements

- **FR-1**: `WebviewSettings` gains `dismissDialogues` (bool, default
  `false`), serialized in `toChannelArgs()` as `dismissDialogues`.
- **FR-2**: A pure-Dart canonical script (`DialogueDismissScript.source`)
  hides top-level `position: fixed`/`position: sticky` elements
  (`display: none`, so removal is reversible) and resets `overflow`/`margin`
  on `documentElement` and `body`.
- **FR-3**: `WebviewService.dismissDialogues({id, policy})` evaluates the
  canonical script through the port, once per policy attempt, with the
  policy delay between attempts.
- **FR-4**: Dismissal requires a created webview (`not_created` typed
  failure otherwise).
- **FR-5**: Errors raised by the port during dismissal are swallowed — the
  operation is best-effort and never propagates.
- **FR-6**: The script must not recurse into iframes or child frames.
- **FR-7**: `DialogueDismissPolicy` exposes `attempts` (default 1, min 1)
  and `delay` (default zero).

### Key Entities

| Entity | Kind | Notes |
|---|---|---|
| `WebviewSettings.dismissDialogues` | typed setting | rides the channel envelope |
| `DialogueDismissScript` | pure Dart | canonical JS source constant |
| `DialogueDismissPolicy` | value object | attempts + delay |
| `WebviewService.dismissDialogues` | facade op | typed, best-effort |

## Success Criteria

- SC-1: Toggling one setting changes the channel contract args.
- SC-2: A caller can clean a loaded page with a single service call.
- SC-3: Default configuration never modifies any DOM.
- SC-4: Dismissal never crashes the caller or the webview.

## Assumptions

- Callers apply dismissal after load settles (zuraffa has no navigation
  event stream yet — spec 004 introduces it; auto-apply on load events is a
  follow-up then).
- Native-side auto-apply from the setting is a native-milestone concern;
  this spec delivers the Dart-side contract and behavior.
