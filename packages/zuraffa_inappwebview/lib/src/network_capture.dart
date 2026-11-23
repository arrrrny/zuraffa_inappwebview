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
/// truncates string bodies (measured in UTF-16 code units; a truncation
/// never splits a surrogate pair).
///
/// Both are clamped to zero, so a negative value cannot reach the ingest
/// listener and blow up as a `RangeError`.
class CaptureBudget {
  final int maxEntries;
  final int maxBodyBytes;

  const CaptureBudget({
    int maxEntries = 500,
    int maxBodyBytes = 50 * 1024,
  })  : maxEntries = maxEntries < 0 ? 0 : maxEntries,
        maxBodyBytes = maxBodyBytes < 0 ? 0 : maxBodyBytes;
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
  /// The raw key is not valid percent-encoding as often as not (a literal
  /// non-ASCII key, `?100%=x`, `%FF`), and decoding it throws — which,
  /// from inside a stream listener, is an unhandled async error rather
  /// than anything a caller can see. An undecodable key is therefore
  /// matched verbatim.
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
      final key = _decodeQueryKey(rawKey);
      kept.add(
        _redactedParamKeys.contains(key.toLowerCase())
            ? '$rawKey=$kRedactionMarker'
            : part,
      );
    }
    return '$base?${kept.join('&')}';
  }

  static String _decodeQueryKey(String rawKey) {
    try {
      return Uri.decodeQueryComponent(rawKey);
    } on FormatException {
      return rawKey;
    } on ArgumentError {
      return rawKey;
    }
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
  final Map<String, Object> _errors = {};

  NetworkCaptureManager({
    this.budget = const CaptureBudget(),
    this.redactAuth = true,
  });

  /// Records entries from [events] under [id], replacing any previous
  /// subscription. Cancel with [detach].
  ///
  /// The adapter streams are *specified* to carry typed errors
  /// (`channel_not_wired`, `malformed_response`); without a handler those
  /// become unhandled async errors, so one is installed and the last
  /// error is readable via [error].
  void attach(String id, Stream<WebviewCaptureEntry> events) {
    _subs[id]?.cancel();
    _errors.remove(id);
    _subs[id] = events.listen(
      (e) => ingest(id, e),
      onError: (Object error, StackTrace _) => _errors[id] = error,
    );
  }

  /// The last stream error observed for [id], if any.
  Object? error(String id) => _errors[id];

  /// Stops recording for [id] (keeps the buffered entries).
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Cancels every subscription (call when the manager is done).
  void dispose() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
  }

  /// Ingests one entry: redact (by default) then enforce the budget.
  void ingest(String id, WebviewCaptureEntry entry) {
    final buffered = _entries.putIfAbsent(id, () => []);
    var e = redactAuth ? _redactor.redact(entry) : entry;
    if (e.requestBody != null &&
        e.requestBody!.length > budget.maxBodyBytes) {
      e = _copyWith(
        e,
        requestBody: _truncate(e.requestBody!, budget.maxBodyBytes),
      );
    }
    if (e.responseBody != null &&
        e.responseBody!.length > budget.maxBodyBytes) {
      e = _copyWith(
        e,
        responseBody: _truncate(e.responseBody!, budget.maxBodyBytes),
      );
    }
    buffered.add(e);
    if (buffered.length > budget.maxEntries) {
      buffered.removeRange(0, buffered.length - budget.maxEntries);
    }
  }

  /// Cuts [body] to at most [maxUnits] UTF-16 code units without splitting
  /// a surrogate pair in half (which would leave a lone surrogate behind).
  static String _truncate(String body, int maxUnits) {
    var end = maxUnits;
    if (end <= 0) return '';
    final unit = body.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
    return body.substring(0, end);
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
