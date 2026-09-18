/// Network capture (spec 005): typed intercepted-traffic entries on the
/// event seam, source-level secret redaction, and capture budgets.
library;

import 'dart:async';

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
  ///
  /// Decoding is tolerant by design: a payload that is not exactly the
  /// documented shape degrades instead of throwing a bare `TypeError`
  /// into a capture stream. Wrongly-typed strings become null, a
  /// non-`int` status is truncated to an `int`, a header whose name or
  /// value is not a string is dropped.
  static WebviewCaptureEntry fromChannelArgs(
    Map<String, Object?> args, {
    DateTime? at,
  }) =>
      WebviewCaptureEntry(
        url: _asString(args['url']) ?? '',
        method: _asString(args['method']) ?? 'GET',
        requestHeaders: _asHeaders(args['requestHeaders']),
        requestBody: _asString(args['requestBody']),
        status: _asInt(args['status']),
        responseHeaders: _asHeaders(args['responseHeaders']),
        responseBody: _asString(args['responseBody']),
        at: at,
      );

  static String? _asString(Object? raw) => raw is String ? raw : null;

  static int? _asInt(Object? raw) =>
      raw is int ? raw : (raw is num ? raw.toInt() : null);

  static Map<String, String> _asHeaders(Object? raw) {
    if (raw is! Map) return const {};
    final headers = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) headers[key] = value;
    }
    return headers;
  }
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
/// truncates string bodies to that many UTF-8 bytes, never splitting a
/// code point.
class CaptureBudget {
  final int maxEntries;
  final int maxBodyBytes;

  const CaptureBudget({
    this.maxEntries = 500,
    this.maxBodyBytes = 50 * 1024,
  });
}

/// Truncates [value] to at most [maxBytes] UTF-8 bytes, dropping the
/// trailing characters that do not fit whole. Slicing code units instead
/// can leave a lone surrogate that strict JSON/UTF-8 consumers reject.
String _truncateUtf8(String value, int maxBytes) {
  if (value.length <= maxBytes) return value;
  var bytes = 0;
  final out = StringBuffer();
  for (final rune in value.runes) {
    final size = rune < 0x80
        ? 1
        : rune < 0x800
            ? 2
            : rune < 0x10000
                ? 3
                : 4;
    if (bytes + size > maxBytes) break;
    bytes += size;
    out.writeCharCode(rune);
  }
  return out.toString();
}

/// Marker substituted for any redacted secret value (zikzak A15).
const String kRedactionMarker = '<redacted>';

const Set<String> _redactedHeaderKeys = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'api-key',
  'x-auth-token',
  'x-access-token',
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
      final key = Uri.decodeQueryComponent(part.substring(0, eq));
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
    if (requestBody != null && requestBody.length > budget.maxBodyBytes) {
      e = _copyWith(
        e,
        requestBody: _truncateUtf8(requestBody, budget.maxBodyBytes),
      );
    }
    final responseBody = e.responseBody;
    if (responseBody != null && responseBody.length > budget.maxBodyBytes) {
      e = _copyWith(
        e,
        responseBody: _truncateUtf8(responseBody, budget.maxBodyBytes),
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
