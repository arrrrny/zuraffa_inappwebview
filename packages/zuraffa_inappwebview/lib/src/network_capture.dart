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
///
/// The filter ships to the platform via `setCaptureEnabled`; [matches] is
/// the client-side counterpart for consumers that want to double-check an
/// entry (the manager itself does not filter — native filtering is
/// authoritative).
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

const Set<String> _redactedHeaderKeys = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'x-csrf-token',
  'x-auth-token',
  'x-amz-security-token',
};

const Set<String> _redactedParamKeys = {
  'api_key',
  'apikey',
  'password',
  'passwd',
  'secret',
  'token',
  'access_token',
  'refresh_token',
  'client_secret',
  'key',
  'signature',
  'sig',
  'hmac',
  'session_id',
  'auth',
};

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
          e.key: _redactedHeaderKeys.contains(e.key.toLowerCase())
              ? kRedactionMarker
              : e.value,
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
      final rawKey = part.substring(0, eq);
      // Urls are page-controlled: a malformed percent-encoding (`%FF`, a
      // truncated sequence) must not throw out of `ingest`, so fall back
      // to the raw key when decoding fails.
      String key;
      try {
        key = Uri.decodeQueryComponent(rawKey);
      } on FormatException {
        key = rawKey;
      } on ArgumentError {
        key = rawKey;
      }
      kept.add(
        _redactedParamKeys.contains(key.toLowerCase())
            ? '$key=$kRedactionMarker'
            : part,
      );
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
  ///
  /// Adapter streams surface typed data-plane errors by contract
  /// (`malformed_response`, `channel_not_wired`); they are contained here so
  /// one bad native payload never becomes an unhandled async error in the
  /// consumer's zone. A caller that subscribes to a stream manually must
  /// pass its own `onError`.
  void attach(String id, Stream<WebviewCaptureEntry> events) {
    _subs[id]?.cancel();
    _subs[id] = events.listen(
      (e) => ingest(id, e),
      onError: (Object error) {
        // Contained: a stream error is data-plane noise, not a reason to
        // tear down the consumer's zone.
        assert(() {
          // ignore: avoid_print
          print('NetworkCaptureManager: capture stream error for $id: $error');
          return true;
        }());
      },
    );
  }

  /// Stops recording for [id] (keeps the buffered entries).
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Ingests one entry: redact (by default) then enforce the budget.
  void ingest(String id, WebviewCaptureEntry entry) {
    final buffered = _entries.putIfAbsent(id, () => []);
    var e = redactAuth ? _redactor.redact(entry) : entry;
    if (e.requestBody != null &&
        utf8.encode(e.requestBody!).length > budget.maxBodyBytes) {
      e = _copyWith(
        e,
        requestBody: _truncateUtf8(e.requestBody!, budget.maxBodyBytes),
      );
    }
    if (e.responseBody != null &&
        utf8.encode(e.responseBody!).length > budget.maxBodyBytes) {
      e = _copyWith(
        e,
        responseBody: _truncateUtf8(e.responseBody!, budget.maxBodyBytes),
      );
    }
    buffered.add(e);
    if (buffered.length > budget.maxEntries) {
      buffered.removeRange(0, buffered.length - budget.maxEntries);
    }
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

/// Truncates [body] to at most [maxBytes] UTF-8 bytes, cutting on a
/// character boundary so no multi-byte sequence is split (a split
/// surrogate would encode to U+FFFD — silent corruption of the body).
String _truncateUtf8(String body, int maxBytes) {
  final bytes = utf8.encode(body);
  if (bytes.length <= maxBytes) return body;
  var end = maxBytes;
  while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}
