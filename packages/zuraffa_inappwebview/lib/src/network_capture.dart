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
  /// Fields are decoded defensively: the envelope is already guarded by the
  /// adapters' typed `malformed_response`, but a drifted *field* would
  /// otherwise escape `asyncMap` as a raw `TypeError` — a stream error no
  /// subscriber can tell apart from a platform bug or catch as a
  /// [WebviewException].
  static WebviewCaptureEntry fromChannelArgs(Map<String, Object?> args) =>
      WebviewCaptureEntry(
        url: _string(args['url']) ?? '',
        method: _string(args['method']) ?? 'GET',
        requestHeaders: _stringMap(args['requestHeaders']),
        requestBody: _string(args['requestBody']),
        status: _int(args['status']),
        responseHeaders: _stringMap(args['responseHeaders']),
        responseBody: _string(args['responseBody']),
      );
}

String? _string(Object? raw) => raw is String ? raw : null;

int? _int(Object? raw) => switch (raw) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v),
      _ => null,
    };

Map<String, String> _stringMap(Object? raw) => raw is! Map
    ? const {}
    : {for (final e in raw.entries) '${e.key}': '${e.value}'};

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
/// truncates string bodies to at most that many UTF-8 bytes.
class CaptureBudget {
  final int maxEntries;

  /// The body cap in UTF-8 bytes — the same unit the filter ships to the
  /// platform as `maxBodyBytes` — applied without splitting a code point.
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
  ///
  /// The fragment is redacted too, and independently of the query: OAuth
  /// implicit flows carry the access token there, while parsing it as a
  /// query both leaks the token and mangles any legitimate `#anchor`.
  String redactUrl(String url) {
    final hash = url.indexOf('#');
    if (hash == -1) return _redactQuery(url);
    return '${_redactQuery(url.substring(0, hash))}'
        '#${_redactParams(url.substring(hash + 1))}';
  }

  /// Redacts the query of [part], which may be a whole URL or a bare query,
  /// and leaves everything before the `?` untouched.
  String _redactQuery(String part) {
    final q = part.indexOf('?');
    if (q == -1) return part;
    return '${part.substring(0, q)}?${_redactParams(part.substring(q + 1))}';
  }

  String _redactParams(String query) {
    final kept = <String>[];
    for (final raw in query.split('&')) {
      final eq = raw.indexOf('=');
      if (eq == -1) {
        kept.add(raw);
        continue;
      }
      final key = Uri.decodeQueryComponent(raw.substring(0, eq));
      kept.add(
        _redactedParamKeys.contains(key.toLowerCase())
            ? '$key=$kRedactionMarker'
            : raw,
      );
    }
    return kept.join('&');
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
    final requestBody = _boundedBody(e.requestBody, budget.maxBodyBytes);
    final responseBody = _boundedBody(e.responseBody, budget.maxBodyBytes);
    if (!identical(requestBody, e.requestBody) ||
        !identical(responseBody, e.responseBody)) {
      e = _copyWith(e, requestBody: requestBody, responseBody: responseBody);
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

String? _boundedBody(String? body, int maxBytes) =>
    body == null ? null : _truncateToBytes(body, maxBytes);

/// Truncates [s] to at most [maxBytes] UTF-8 bytes, never splitting a code
/// point. `.length`/`substring` count UTF-16 code units — the same field is
/// a *byte* cap on the platform side — so measuring in code units would let
/// the bounded buffer (SC-2) grow up to 4× past its bound and could leave a
/// lone surrogate that no longer round-trips through UTF-8.
String _truncateToBytes(String s, int maxBytes) {
  var used = 0;
  var end = 0;
  for (final rune in s.runes) {
    final width = rune <= 0x7F
        ? 1
        : rune <= 0x7FF
            ? 2
            : rune <= 0xFFFF
                ? 3
                : 4;
    if (used + width > maxBytes) break;
    used += width;
    end += rune > 0xFFFF ? 2 : 1; // a surrogate pair is two code units
  }
  return end >= s.length ? s : s.substring(0, end);
}
