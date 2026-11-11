# Implementation Plan: VCR Record/Replay

**Branch**: `008-vcr-record-replay` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

## Summary

`Cassette` (formatVersion 1, JSON round-trip) + `VcrRecorder` (004/005
streams + service html/cookie snapshots; defensive re-redaction) +
`VcrReplayer` (exact → path-prefix best-match serving via a new
`loadHtml` port op; synthesized capture events on a broadcast stream;
`vcr_unmatched` typed failure, soft mode opt-out).

## Project Structure

```text
app: lib/src/vcr_record_replay.dart   # NEW
     lib/src/webview_port.dart        # + loadHtml
     lib/src/webview_service.dart     # + op + unwired
adapters ×3: loadHtml envelope call + tests
test: vcr_record_replay_test.dart
```

## Model

| Piece | Shape |
|---|---|
| CassetteEntry | url, html, cookies[], captures[] (captures attach to the navigation they preceded) |
| Cassette | `{formatVersion: 1, entries: [...]}` |
| recorder | record(navigationEvents, captureEvents) / ingestCapture / ingestNavigation / stop |
| replayer | loadUrl(url) → bestMatch → service.loadHtml + synthesized captures; strict flag |

## MVP

US1+US2 (record + offline replay), US3 (matching discipline), US4
(loadHtml adapter contract) — one cycle.

## Risks

- Port widening (`loadHtml`) churned fakes; mechanical.
- Best-match is path-prefix based; request normalization defers.
