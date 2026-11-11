# Implementation Plan: Screenshot & PDF Export

**Branch**: `003-screenshot-pdf-export` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

Two new port operations (`takeScreenshot`, `exportPdf`) riding the shared
channel envelope, a `ScreenshotConfiguration` value object (format/quality),
service facade ops with the `not_created` guard, and identical adapter
mapping in android/ios/macos (method name, `data` byte-list decode,
`malformed_response` on non-list payloads, null passthrough).

## Technical Context

**Language/Version**: Dart 3.13 (pure Dart) · **Dependencies**: none new
**Testing**: `dart test` per package; scripted invoke maps for adapters
**Constraints**: bytes are `List<int>` inside the envelope map (`data` key);
null return is the capture-failure contract (never an untyped throw)

## Project Structure

```text
packages/zuraffa_inappwebview/
  lib/src/webview_types.dart     # + ScreenshotFormat, ScreenshotConfiguration
  lib/src/webview_port.dart      # + takeScreenshot, exportPdf (abstract)
  lib/src/webview_service.dart   # + facade ops (not_created guard)
  lib/src/webview_service.dart   # UnwiredWebviewPort: + port_not_wired
  test/screenshot_pdf_test.dart  # NEW behaviors
packages/zuraffa_inappwebview_{android,ios,macos}/
  lib/src/<platform>_webview_port.dart  # + envelope mapping (same shape)
  test/<platform>_webview_adapter_test.dart  # + scripted behaviors
```

## Data model / contract

| Piece | Shape |
|---|---|
| `ScreenshotFormat` | `enum { png, jpeg }` → `'png'/'jpeg'` |
| `ScreenshotConfiguration` | `format` (png), `quality` (100) → `{'format':…, 'quality':…}` |
| `takeScreenshot` args | `{'id':…, …configArgs}` (config omitted when null) |
| `exportPdf` args | `{'id':…}` |
| response | `{'data': List<int>?}` — null passthrough |

## MVP Definition

US1 (port + service passthrough + guard) is the MVP; US2/US3 (config,
adapter mapping) land in the same cycle immediately after.

## Risks

- Envelope maps carry `Object?` — byte lists must be validated as `List`
  before cast (house `malformed_response` pattern, as in `getCookies`).
