# Implementation Plan: Network Capture

**Branch**: `005-network-capture` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

Typed capture entries on the spec-004 event seam: `setCaptureEnabled`
call op (+filter args), `captureEvents` stream op, and a pure-Dart
`NetworkCaptureManager` applying source-level redaction (zikzak A15 key
lists) and capture budgets (maxEntries keeps latest, maxBodyBytes
truncates) at ingestion.

## Project Structure

```text
app: lib/src/network_capture.dart   # NEW: entry, filter, budget, redactor, manager
     lib/src/webview_port.dart      # + setCaptureEnabled, captureEvents
     lib/src/webview_service.dart   # + ops + unwired
     test/network_capture_test.dart # NEW
adapters ×3: port + setCaptureEnabled call / captureEvents decode (004 shape)
             test additions
```

## Data model

| Piece | Shape |
|---|---|
| entry | url, method, requestHeaders `Map<String,String>`, requestBody?, status int?, responseHeaders, responseBody?, at |
| filter | urlPattern (substring, case-insensitive), maxBodyBytes int? |
| budget | maxEntries (default 500, keep latest), maxBodyBytes (default 50 KB truncate) |
| redactor | header keys + query param keys → `<redacted>` |

## MVP

US1–US3 (seam + manager + redaction) then US4 (adapters).

## Risks

- Port widening churns the four test fakes again (mechanical).
