# Feature Specification: Screenshot & PDF Export

**Feature Branch**: `003-screenshot-pdf-export`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 001 ("Implement the export
PDF and take screenshot… ios, android, macos is priority"), reshaped for the
clean API: two new port operations (`takeScreenshot`, `exportPdf`) that ride
the shared channel envelope and surface typed byte payloads through
`WebviewService`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture the rendered page (Priority: P1)

A scraping caller has a loaded headless webview and calls
`service.takeScreenshot(id: 'scraper')`. The port evaluates the capture on
the platform and the service returns the raw image bytes (`List<int>`,
PNG by default), or null when the platform could not capture (mirroring
zikzak's nullable `takeScreenshot`). Unknown ids fail the typed
`not_created` guard before any platform call.

**Why this priority**: Byte capture is the feature; everything else is
configuration around it.

**Independent Test**: Fake port scripted to return bytes; assert passthrough,
null passthrough, and the `not_created` guard.

**Acceptance Scenarios**:

1. **Given** a created webview, **When** `takeScreenshot(id)` is called,
   **Then** the port receives `takeScreenshot` with the id and the service
   returns the port's byte payload unchanged.
2. **Given** the platform returns null (capture failed), **When**
   `takeScreenshot(id)` is called, **Then** the service returns null (no
   throw — nullability is the contract).
3. **Given** an id that was never created, **When** `takeScreenshot(id)` is
   called, **Then** it throws the typed `not_created` failure.

---

### User Story 2 - Capture configuration (Priority: P2)

A caller wants a JPEG at quality 80:
`service.takeScreenshot(id, config: ScreenshotConfiguration(format: ScreenshotFormat.jpeg, quality: 80))`.
The configuration serializes to channel args (`format`, `quality`) with
pinned defaults (png, quality 100); the adapter forwards it verbatim.

**Why this priority**: Format/quality covers the real capture needs
(thumbnails, small transfers); rect-capture is a documented follow-up.

**Independent Test**: Assert `ScreenshotConfiguration.toChannelArgs()` and
adapter arg forwarding.

**Acceptance Scenarios**:

1. **Given** default `ScreenshotConfiguration`, **When** serialized,
   **Then** args are `{'format': 'png', 'quality': 100}`.
2. **Given** jpeg quality 80, **When** the adapter calls the envelope,
   **Then** method `takeScreenshot` carries `id`, `format: 'jpeg'`,
   `quality: 80`.
3. **Given** a config, **When** `exportPdf(id)` runs, **Then** it is
   unaffected (no config in the PDF MVP).

---

### User Story 3 - Adapter envelope mapping (Priority: P2)

Every platform adapter (android/ios/macos) maps the two new operations onto
the shared envelope: method names `takeScreenshot` / `exportPdf`, response
key `data` carrying the byte list, null passthrough, and a non-list `data`
payload raising the adapter's typed `malformed_response` failure. The
unwired port surfaces `port_not_wired` for both ops.

**Why this priority**: The envelope contract is what the native shells
implement; pinning it keeps the three adapters honest.

**Independent Test**: Scripted invoke maps per adapter (house pattern).

**Acceptance Scenarios**:

1. **Given** a scripted `{'data': [1, 2, 3]}` response, **When** the adapter
   port takes a screenshot, **Then** `[1, 2, 3]` is returned.
2. **Given** a scripted `{'data': 'oops'}` response, **When** the adapter
   port takes a screenshot, **Then** the adapter's typed
   `malformed_response` failure is thrown.
3. **Given** the unwired port, **When** either op is called, **Then**
   `port_not_wired` surfaces.

---

## Requirements

- **FR-1**: `WebviewPort.takeScreenshot({required id, ScreenshotConfiguration? config})` → `Future<List<int>?>`.
- **FR-2**: `WebviewPort.exportPdf({required id})` → `Future<List<int>?>`.
- **FR-3**: `ScreenshotConfiguration` (format: png default, quality: 100 default, clamped to 1–100) serializes as `format`/`quality` channel args.
- **FR-4**: `WebviewService` exposes both ops with the `not_created` guard, passing config and bytes through unchanged.
- **FR-5**: Adapters forward `takeScreenshot`/`exportPdf` with id (+ config args) and decode the `data` key; non-list `data` → typed `malformed_response`; null stays null.
- **FR-6**: `UnwiredWebviewPort` raises `port_not_wired` for both ops.

### Key Entities

| Entity | Kind | Channel shape |
|---|---|---|
| `ScreenshotFormat` | enum | `'png' | 'jpeg'` |
| `ScreenshotConfiguration` | value object | `{'format': String, 'quality': int}` |
| port ops | interface | methods `takeScreenshot`/`exportPdf`, response key `data: List<int>?` |

## Success Criteria

- SC-1: A caller can capture PNG bytes of a loaded page with one call.
- SC-2: JPEG/quality configuration rides the same call.
- SC-3: All three adapters + unwired port honor the identical contract.
- SC-4: Capture failure is a null return, never an untyped crash.

## Assumptions

- Rect capture (partial viewport) is a follow-up behind the same op.
- PDF configuration (paper size etc.) is deferred until a consumer needs it.
- Native handlers are the native milestone; this spec pins the Dart contract.
