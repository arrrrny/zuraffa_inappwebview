# Feature Specification: Network Capture — Mission-Grade Intercept

**Feature Branch**: `005-network-capture`

**Created**: 2026-09-17

**Status**: Draft

**Input**: Ported from `zikzak_inappwebview` spec 010 + the
`NetworkCaptureManager`/`secret_redactor` module tier (SPLIT_MAP
`CaptureSource` port). The zikzak engine (pure-Dart JS injector,
headless-capable) intercepts a page's own XHR/fetch traffic so an agent can
turn an unknown site's API calls into structured intelligence. This spec
ports the Dart-side product: typed capture entries on the event seam
(spec 004), an enable/disable port op, source-level secret redaction,
per-webview capture budgets, and a filter. Distillation (Sightings),
streaming early-return, and salvage flush are follow-ups behind the same
seams.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Typed capture entries on the event seam (Priority: P1)

A caller enables capture on a headless webview
(`service.setCaptureEnabled(id: 'scraper', enabled: true)`) and subscribes
to `service.captureEvents(id: 'scraper')`. The platform pushes one typed
`WebviewCaptureEntry` per intercepted XHR/fetch: url, method, request
headers/body, response status/headers/body, timestamp. Unknown ids fail
`not_created`; the unwired port surfaces `port_not_wired`; a filter
(url substring, max body bytes) rides the enable call as channel args.

**Why this priority**: The typed entry + stream is the intelligence
artifact; every consumer (agent tools, VCR, distillation) reads it.

**Independent Test**: Fake port with a capture stream; scripted adapter
invoke maps.

**Acceptance Scenarios**:

1. **Given** channel args for one intercepted call, **When** decoded,
   **Then** the entry carries url/method/headers/bodies/status/at.
2. **Given** `setCaptureEnabled(id, enabled: true, filter)`, **When** the
   port receives it, **Then** the adapter ships method `setCaptureEnabled`
   with `id`, `enabled`, and the filter's serialized args.
3. **Given** an unknown id, **When** either op is called, **Then**
   `not_created` throws (stream op throws before subscribing).
4. **Given** the unwired port, **When** either op is called, **Then**
   `port_not_wired` surfaces.

---

### User Story 2 - The capture manager: buffer + budgets (Priority: P1)

A caller wraps the stream in `NetworkCaptureManager` (or feeds it via
`ingest` — pure, no webview needed). The manager buffers entries per
webview id in order and enforces a `CaptureBudget`: at most `maxEntries`
entries are retained (the latest win when the budget overflows), and
string bodies longer than `maxBodyBytes` are truncated at ingestion.

**Why this priority**: Unbounded capture buffers are the real-world
failure (retailer pages emit hundreds of MB); budgets make the feature
mission-safe.

**Independent Test**: Ingest synthetic entries; assert retention +
truncation.

**Acceptance Scenarios**:

1. **Given** ingested entries in order, **When** `entries(id)` is read,
   **Then** they come back in ingestion order; `clear(id)` empties them.
2. **Given** `maxEntries: 2` and 3 ingested, **When** read, **Then** the
   latest 2 remain.
3. **Given** `maxBodyBytes: 10` and a body of 100 ASCII bytes, **When**
   ingested, **Then** the stored body is 10 bytes; a multi-byte body is cut
   on a character boundary so no character is split.

---

### User Story 3 - Source-level secret redaction (Priority: P1)

Auth-shaped secrets are redacted **at the source, before any consumer
observes them** (zikzak A15, widened): header keys
`authorization/proxy-authorization/cookie/set-cookie` plus
`x-api-key/x-csrf-token/x-auth-token/x-amz-security-token`, and URL query
params
`api_key/apikey/password/passwd/secret/token/access_token/refresh_token/client_secret`
plus `key/signature/sig/hmac/session_id/auth` become `<redacted>` at
ingestion. Redaction is on by default and can be disabled for trusted
contexts. A malformed percent-encoding in a query key never throws: the
redactor falls back to the raw key.

**Why this priority**: Capture output feeds logs, cassettes, and agent
contexts — leaking bearer tokens there is the catastrophic failure.

**Independent Test**: Ingest an entry carrying an Authorization header and
a `?token=…` url; assert both are redacted in `entries()`.

**Acceptance Scenarios**:

1. **Given** an entry with `Authorization: Bearer xyz` and
   `Cookie: a=b`, **When** ingested (default), **Then** both header values
   read `<redacted>` while other headers survive verbatim.
2. **Given** url `https://x.dev/p?token=abc&keep=1`, **When** ingested
   (default), **Then** the stored url has `token=<redacted>` and
   `keep=1`.
3. **Given** `redactAuth: false`, **When** ingested, **Then** values
   survive verbatim.

---

### User Story 4 - Adapter contract ×3 (Priority: P2)

android/ios/macos pin the channel contract: call method
`setCaptureEnabled` (`id`, `enabled`, filter args), event method
`captureEvents` with the entry payload + `id`, non-map event → typed
`malformed_response`, missing event source → typed `channel_not_wired`.

**Independent Test**: Scripted channels per adapter.

**Acceptance Scenarios**:

1. **Given** a scripted event `{'id':'w','url':…,'method':'GET',…}`,
   **When** subscribed, **Then** the decoded typed entry arrives; raw
   payloads are filtered by `id` before decoding, so a foreign payload can
   never error this subscription.
2. **Given** a non-map event, **When** subscribed, **Then** the stream
   errors `malformed_response`.
3. **Given** no event source, **When** subscribing, **Then**
   `channel_not_wired`.

---

## Requirements

- **FR-1**: `WebviewCaptureEntry` + codec; `WebviewCaptureFilter` (urlPattern, maxBodyBytes) serializable.
- **FR-2**: Port ops `setCaptureEnabled` + `captureEvents`; service guards; unwired failures.
- **FR-3**: `NetworkCaptureManager` — attach/detach/ingest/entries/clear; `CaptureBudget` (maxEntries keeps latest, maxBodyBytes truncates to UTF-8 bytes on a character boundary) applied at ingest; `attach` contains stream errors.
- **FR-4**: `CaptureSecretRedactor` semantics as US3 (marker `<redacted>`, case-insensitive key match, tolerant of malformed percent-encoding), applied at ingest by default.
- **FR-5**: Adapter mapping per US4.

### Key Entities

| Entity | Kind | Channel shape |
|---|---|---|
| `WebviewCaptureEntry` | value object | `{'url','method','requestHeaders','requestBody','status','responseHeaders','responseBody'}` |
| `WebviewCaptureFilter` | value object | `{'urlPattern','maxBodyBytes'}` |
| `CaptureBudget` | value object | n/a (Dart-side policy) |
| `CaptureSecretRedactor` | pure functions | n/a |

## Success Criteria

- SC-1: One subscription yields the typed traffic record for a webview.
- SC-2: Budgets make the buffer bounded under hostile page loads.
- SC-3: No auth-shaped secret ever reaches a consumer by default.
- SC-4: The contract is identical across adapters.

## Assumptions

- Distillation (Sightings), streaming early-return, salvage flush, and
  per-domain budget keying are follow-ups behind these seams.
- The JS injector + native event push are the native milestone.
