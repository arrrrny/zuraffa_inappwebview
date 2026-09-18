# Test List — 004 navigation-tracking

| ID | Behavior | Task | Status |
|---|---|---|---|
| N1 | codec decodes started/completed/failed + isMainFrame default + errorCode; unrecognized phase decodes to null (no phantom `started`); wrong-typed fields fail typed | T001 | DONE |
| N2 | service passthrough streams typed events; `not_created` for unknown id; unwired `port_not_wired` | T002 | DONE |
| N3 | tracker records ordered visits; lastUrl reflects latest | T004 | DONE |
| N4 | same url within dedup window collapses to earliest entry | T005 | DONE |
| N5 | mainFrameOnly drops sub-frame events by default | T006 | DONE |
| N6 | hasCycle true for A→B→A, false for A→B→C; detach stops recording | T007 | DONE |
| N7a | android adapter: id-filtered decode (id filter before key decode), malformed on non-map or wrong-typed fields, channel_not_wired without source | T008 | DONE |
| N7b | ios adapter: same | T009 | DONE |
| N7c | macos adapter: same | T010 | DONE |
| N8 | `clear(id)` drops one record; `dispose()` drops all records + cancels subscriptions | T007 | DONE |

Counts: 11 behaviors — 11 driven red → green, 0 remaining.
