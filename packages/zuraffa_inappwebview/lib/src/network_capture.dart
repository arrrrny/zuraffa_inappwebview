/// Network capture (spec 005): typed intercepted-traffic entries on the
/// event seam, source-level secret redaction, and capture budgets.
library;

import 'dart:async';
import 'dart:convert';

/// One intercepted XHR/fetch exchange pushed by the platform.
class WebviewCaptureEntry {
  final String url;
  final String method;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final int? status;
  final Map<String, String> responseHeaders;
  final String? responseBody;
  final DateTime at;

  WebviewCaptureEntry({
    required this.url,
    required this.method,
    this.requestHeaders = const {},
    this.requestBody,
    this.status,
    this.responseHeaders = const {},
    this.responseBody,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// Codec from channel args (event method `captureEvents`).
  static WebviewCaptureEntry fromChannelArgs(Map<String, Object?> args) =>
      WebviewCaptureEntry(
        url: args['url'] as String? ?? '',
        method: args['method'] as String? ?? 'GET',
        requestHeaders:
            Map<String, String>.from(args['requestHeaders'] as Map? ?? {}),
        requestBody: args['requestBody'] as String?,
        status: args['status'] as int?,
        responseHeaders:
            Map<String, String>.from(args['responseHeaders'] as Map? ?? {}),
        responseBody: args['responseBody'] as String?,
      );
}

/// Capture filter riding the enable call (spec 005 FR-1): a
/// case-insensitive URL substring plus a body byte cap.
class WebviewCaptureFilter {
  final String? urlPattern;
  final int? maxBodyBytes;

  const WebviewCaptureFilter({this.urlPattern, this.maxBodyBytes});

  Map<String, Object?> toChannelArgs() => {
        if (urlPattern != null) 'urlPattern': urlPattern,
        if (maxBodyBytes != null) 'maxBodyBytes': maxBodyBytes,
      };

  /// Whether [entry] passes the URL pattern (absent pattern = match all).
  bool matches(WebviewCaptureEntry entry) => urlPattern == null ||
      entry.url.toLowerCase().contains(urlPattern!.toLowerCase());
}

/// Bounded retention policy applied at ingestion (spec 005 FR-3):
/// [maxEntries] keeps the latest entries when exceeded; [maxBodyBytes]
/// truncates string bodies to that many UTF-8 bytes.
class CaptureBudget {
  final int maxEntries;
  final int maxBodyBytes;

  const CaptureBudget({
    this.maxEntries = 500,
    this.maxBodyBytes = 50 * 1024,
  });
}

/// Marker substituted for any redacted secret value (zikzak A15).
const String kRedactionMarker = '<redacted>';

/// Case-insensitive fragments that mark a header or query-param name as
/// auth-shaped.
///
/// Names are matched on shape rather than by a fixed allowlist: the
/// allowlist kept losing the race with new spellings, and `x-api-key`,
/// `api-key`, `x-auth-token`, `x-goog-api-key`, `proxy-authenticate`,
/// `private_key`, `id_token` and `sessionid` all reached consumers
/// verbatim. A name that merely looks secret is redacted — the fail-safe
/// direction for a value that is otherwise durable in a VCR cassette.
const List<String> _secretNameFragments = [
  'key',
  'secret',
  'token',
  'auth',
  'password',
  'passwd',
  'cookie',
  'session',
  'sig',
];

bool _isSecretName(String name) =>
    _secretNameFragments.any(name.toLowerCase().contains);

/// Source-level redaction of auth-shaped secrets (spec 005 FR-4):
/// redactable header values and URL query params become `<redacted>`
/// before any consumer observes the entry.
class CaptureSecretRedactor {
  const CaptureSecretRedactor();

  WebviewCaptureEntry redact(WebviewCaptureEntry entry) => WebviewCaptureEntry(
        url: redactUrl(entry.url),
        method: entry.method,
        requestHeaders: _redactHeaders(entry.requestHeaders),
        requestBody: entry.requestBody,
        status: entry.status,
        responseHeaders: _redactHeaders(entry.responseHeaders),
        responseBody: entry.responseBody,
        at: entry.at,
      );

  Map<String, String> _redactHeaders(Map<String, String> headers) => {
        for (final e in headers.entries)
          e.key: _isSecretName(e.key) ? kRedactionMarker : e.value,
      };

  /// Redacts auth-shaped query parameters, preserving structure and
  /// non-secret params. Rebuilt as a raw string so the marker is not
  /// percent-encoded by Uri canonicalization.
  String redactUrl(String url) {
    final q = url.indexOf('?');
    if (q == -1) return url;
    final base = url.substring(0, q);
    final kept = <String>[];
    for (final part in url.substring(q + 1).split('&')) {
      final eq = part.indexOf('=');
      if (eq == -1) {
        kept.add(part);
        continue;
      }
      final key = Uri.decodeQueryComponent(part.substring(0, eq));
      kept.add(_isSecretName(key) ? '$key=$kRedactionMarker' : part);
    }
    return '$base?${kept.join('&')}';
  }
}

/// Buffers typed capture entries per webview id, applying redaction and
/// budgets at ingestion (spec 005). Works without a webview via [ingest];
/// [attach] wires a capture event stream.
class NetworkCaptureManager {
  final CaptureBudget budget;
  final bool redactAuth;
  final CaptureSecretRedactor _redactor = const CaptureSecretRedactor();

  final Map<String, List<WebviewCaptureEntry>> _entries = {};
  final Map<String, StreamSubscription<WebviewCaptureEntry>> _subs = {};

  NetworkCaptureManager({
    this.budget = const CaptureBudget(),
    this.redactAuth = true,
  });

  /// Records entries from [events] under [id], replacing any previous
  /// subscription. Cancel with [detach].
  void attach(String id, Stream<WebviewCaptureEntry> events) {
    _subs[id]?.cancel();
    _subs[id] = events.listen((e) => ingest(id, e));
  }

  /// Stops recording for [id] (keeps the buffered entries).
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Ingests one entry: redact (by default) then enforce the budget.
  void ingest(String id, WebviewCaptureEntry entry) {
    final buffered = _entries.putIfAbsent(id, () => []);
    var e = redactAuth ? _redactor.redact(entry) : entry;
    final requestBody = e.requestBody;
    if (requestBody != null) {
      final capped = _truncateToBytes(requestBody, budget.maxBodyBytes);
      if (capped.length != requestBody.length) {
        e = _copyWith(e, requestBody: capped);
      }
    }
    final responseBody = e.responseBody;
    if (responseBody != null) {
      final capped = _truncateToBytes(responseBody, budget.maxBodyBytes);
      if (capped.length != responseBody.length) {
        e = _copyWith(e, responseBody: capped);
      }
    }
    buffered.add(e);
    if (buffered.length > budget.maxEntries) {
      buffered.removeRange(0, buffered.length - budget.maxEntries);
    }
  }

  /// Truncates [body] to at most [maxBytes] UTF-8 bytes, cutting on a
  /// code-point boundary.
  ///
  /// A plain `substring` counts UTF-16 code units — up to 4× the
  /// advertised cap for non-ASCII payloads — and can split a surrogate
  /// pair, leaving an unpaired surrogate that throws when the entry is
  /// JSON-encoded into a cassette.
  static String _truncateToBytes(String body, int maxBytes) {
    final encoded = utf8.encode(body);
    if (encoded.length <= maxBytes) return body;
    if (maxBytes <= 0) return '';
    var end = maxBytes;
    while (end > 0 && (encoded[end] & 0xC0) == 0x80) {
      end--;
    }
    return utf8.decode(encoded.sublist(0, end));
  }

  /// The buffered entries for [id] in ingestion order (unmodifiable).
  List<WebviewCaptureEntry> entries(String id) =>
      List.unmodifiable(_entries[id] ?? const []);

  /// Drops every buffered entry for [id].
  void clear(String id) => _entries[id]?.clear();

  WebviewCaptureEntry _copyWith(
    WebviewCaptureEntry e, {
    String? requestBody,
    String? responseBody,
  }) =>
      WebviewCaptureEntry(
        url: e.url,
        method: e.method,
        requestHeaders: e.requestHeaders,
        requestBody: requestBody ?? e.requestBody,
        status: e.status,
        responseHeaders: e.responseHeaders,
        responseBody: responseBody ?? e.responseBody,
        at: e.at,
      );
}
