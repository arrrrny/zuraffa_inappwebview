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

  /// Codec from channel args (event method `captureEvents`). A missing or
  /// unparseable `at` falls back to now — old cassettes stay readable.
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
        at: switch (args['at']) {
          final String raw => DateTime.tryParse(raw),
          _ => null,
        },
      );
}

/// Capture filter riding the enable call (spec 005 FR-1): a
/// case-insensitive URL substring plus a body byte cap. The filter only
/// travels over the channel — applying it is the platform's job.
class WebviewCaptureFilter {
  final String? urlPattern;
  final int? maxBodyBytes;

  const WebviewCaptureFilter({this.urlPattern, this.maxBodyBytes});

  Map<String, Object?> toChannelArgs() => {
        if (urlPattern != null) 'urlPattern': urlPattern,
        if (maxBodyBytes != null) 'maxBodyBytes': maxBodyBytes,
      };
}

/// Bounded retention policy applied at ingestion (spec 005 FR-3):
/// [maxEntries] keeps the latest entries when exceeded; [maxBodyBytes]
/// truncates string bodies to that many UTF-8 bytes, on a rune boundary.
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
  /// percent-encoded by Uri canonicalization. Any `#fragment` is split off
  /// first so a redacted param never swallows it.
  String redactUrl(String url) {
    final hash = url.indexOf('#');
    final fragment = hash == -1 ? '' : url.substring(hash);
    final rest = hash == -1 ? url : url.substring(0, hash);
    final q = rest.indexOf('?');
    if (q == -1) return url;
    final base = rest.substring(0, q);
    final kept = <String>[];
    for (final part in rest.substring(q + 1).split('&')) {
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
    return '$base?${kept.join('&')}$fragment';
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
      final capped = _truncateToByteBudget(requestBody, budget.maxBodyBytes);
      if (capped != requestBody) e = _copyWith(e, requestBody: capped);
    }
    final responseBody = e.responseBody;
    if (responseBody != null) {
      final capped = _truncateToByteBudget(responseBody, budget.maxBodyBytes);
      if (capped != responseBody) e = _copyWith(e, responseBody: capped);
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

/// Truncates [s] to at most [maxBytes] UTF-8 bytes, stopping on a rune
/// boundary so a multi-byte rune (and its surrogate pair) is never cut in
/// half.
String _truncateToByteBudget(String s, int maxBytes) {
  if (utf8.encode(s).length <= maxBytes) return s;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in s.runes) {
    final size = utf8.encode(String.fromCharCode(rune)).length;
    if (used + size > maxBytes) break;
    buffer.writeCharCode(rune);
    used += size;
  }
  return buffer.toString();
}
