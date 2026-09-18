# Test List — 004 navigation-tracking

| ID | Behavior | Task | Status |
|---|---|---|---|
| N1 | codec decodes started/completed/failed + isMainFrame default + errorCode | T001 | DONE |
| N2 | service passthrough streams typed events; `not_created` for unknown id; unwired `port_not_wired` | T002 | DONE |
| N3 | tracker records ordered visits; lastUrl reflects latest | T004 | DONE |
| N4 | same url within dedup window collapses to earliest entry | T005 | DONE |
| N5 | mainFrameOnly drops sub-frame events by default | T006 | DONE |
| N6 | hasCycle true for A→B→A, false for A→B→C; detach stops recording | T007 | DONE |
| N7a | android adapter: id-filtered decode, malformed on non-map, channel_not_wired without source | T008 | DONE |
| N7b | ios adapter: same | T009 | DONE |
| N7c | macos adapter: same | T010 | DONE |
| N8 | unknown navigation `type` decodes to `unknown` (never mislabelled `started`); `clear(id)` drops the record | T011 | DONE |
| N9 | `attach` contains stream errors and recording continues | T012 | DONE |

Counts: 11 behaviors (N7×3 counted per platform), 11 DONE.
