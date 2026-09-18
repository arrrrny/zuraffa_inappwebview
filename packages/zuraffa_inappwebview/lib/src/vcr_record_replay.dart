/// VCR (spec 008): record a live headless session into a versioned
/// cassette; replay it deterministically, offline, through `loadHtml`.
library;

import 'dart:async';

import 'network_capture.dart';
import 'navigation_tracking.dart';
import 'webview_exception.dart';
import 'webview_service.dart';
import 'webview_types.dart';

/// One recorded navigation: the url, served HTML, cookie snapshot, and
/// the capture entries observed since the previous navigation.
class CassetteEntry {
  final String url;
  final String html;
  final List<WebviewCookie> cookies;
  final List<WebviewCaptureEntry> captures;

  const CassetteEntry({
    required this.url,
    required this.html,
    this.cookies = const [],
    this.captures = const [],
  });

  Map<String, Object?> toJson() => {
        'url': url,
        'html': html,
        'cookies': [for (final c in cookies) c.toChannelArgs()],
        'captures': [for (final c in captures) _captureToJson(c)],
      };

  static CassetteEntry fromJson(Map<String, Object?> json) => CassetteEntry(
        url: json['url'] as String? ?? '',
        html: json['html'] as String? ?? '',
        cookies: [
          for (final c in (json['cookies'] as List? ?? const []))
            WebviewCookie.fromChannelArgs(
                Map<String, Object?>.from(c as Map)),
        ],
        captures: [
          for (final c in (json['captures'] as List? ?? const []))
            WebviewCaptureEntry.fromChannelArgs(
                Map<String, Object?>.from(c as Map)),
        ],
      );

  static Map<String, Object?> _captureToJson(WebviewCaptureEntry c) => {
        'url': c.url,
        'method': c.method,
        'requestHeaders': c.requestHeaders,
        if (c.requestBody != null) 'requestBody': c.requestBody,
        if (c.status != null) 'status': c.status,
        'responseHeaders': c.responseHeaders,
        if (c.responseBody != null) 'responseBody': c.responseBody,
      };
}

/// A versioned, JSON-portable recording of one headless session.
///
/// A cassette is plaintext: cookie values, `localStorage` and captured
/// bodies are stored exactly as recorded (auth-shaped secrets in captures
/// are redacted, cookies are not). Treat a cassette as sensitive and
/// persist it somewhere appropriately protected.
class Cassette {
  static const int currentFormatVersion = 1;

  final int formatVersion;
  final List<CassetteEntry> entries;

  const Cassette({this.formatVersion = currentFormatVersion, this.entries = const []});

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'entries': [for (final e in entries) e.toJson()],
      };

  /// Decodes a cassette payload.
  ///
  /// The version is *checked*, not copied through: a future v2 cassette
  /// fails as `cassette_version` instead of being silently replayed under
  /// v1 rules, and a foreign shape fails as `malformed_response` instead
  /// of escaping as an untyped `TypeError`.
  static Cassette fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'] ?? currentFormatVersion;
    if (version is! int || version != currentFormatVersion) {
      throw WebviewException(
        'cassette_version',
        'Cassette format version $version is not supported '
        '(this build reads v$currentFormatVersion).',
        recoverable: false,
      );
    }
    try {
      return Cassette(
        formatVersion: version,
        entries: [
          for (final e in (json['entries'] as List? ?? const []))
            CassetteEntry.fromJson(Map<String, Object?>.from(e as Map)),
        ],
      );
    } on Object catch (error) {
      throw WebviewException(
        'malformed_response',
        'The cassette payload could not be decoded: $error',
        recoverable: false,
      );
    }
  }
}

/// Records a live session into a [Cassette] (spec 008). Watches the
/// webview's navigation + capture streams; each completed main-frame
/// navigation freezes an entry with html/cookie snapshots and the
/// captures observed since the previous navigation. Capture payloads are
/// defensively re-redacted (the 005 redactor).
///
/// Navigations are ingested strictly in order: [ingestNavigation] awaits
/// two service round-trips before touching the buffers, and redirect
/// chains emit several completed events in quick succession, so the
/// ingestions are serialised on an internal chain and [stop] drains it.
///
/// One recorder records one session — construct a fresh recorder per
/// recording rather than calling [record] again after [stop].
class VcrRecorder {
  final WebviewService service;
  final String webviewId;
  final CaptureSecretRedactor _redactor = const CaptureSecretRedactor();

  final List<CassetteEntry> _entries = [];
  final List<WebviewCaptureEntry> _pendingCaptures = [];
  final List<StreamSubscription> _subs = [];
  final List<Object> _errors = [];
  Future<void> _ingestChain = Future<void>.value();

  VcrRecorder({required this.service, required this.webviewId});

  /// Errors observed on the watched streams, or raised while ingesting an
  /// entry. Nothing here is thrown at the caller: a disposed webview or a
  /// channel hiccup mid-recording captures an error instead of taking
  /// down the recording (and the process).
  List<Object> get errors => List.unmodifiable(_errors);

  /// Starts watching [navigationEvents] and [captureEvents].
  void record({
    required Stream<WebviewNavigationEvent> navigationEvents,
    required Stream<WebviewCaptureEntry> captureEvents,
  }) {
    _subs.add(captureEvents.listen(
      ingestCapture,
      onError: (Object error, StackTrace _) => _errors.add(error),
    ));
    _subs.add(navigationEvents.listen(
      (event) {
        _ingestChain = _ingestChain.then((_) => _ingestSafely(event));
      },
      onError: (Object error, StackTrace _) => _errors.add(error),
    ));
  }

  Future<void> _ingestSafely(WebviewNavigationEvent event) async {
    try {
      await ingestNavigation(event);
    } on Object catch (error) {
      _errors.add(error);
    }
  }

  /// Buffers one capture (redacted defensively) for the next entry.
  void ingestCapture(WebviewCaptureEntry entry) =>
      _pendingCaptures.add(_redactor.redact(entry));

  /// Freezes an entry for a completed main-frame navigation.
  Future<void> ingestNavigation(WebviewNavigationEvent event) async {
    if (event.phase != WebviewNavigationPhase.completed ||
        !event.isMainFrame) {
      return;
    }
    final html = await service.getHtml(id: webviewId) ?? '';
    final cookies =
        await service.getCookies(url: event.url);
    _entries.add(CassetteEntry(
      url: event.url,
      html: html,
      cookies: List.of(cookies),
      captures: List.of(_pendingCaptures),
    ));
    _pendingCaptures.clear();
  }

  /// Stops watching, drains any in-flight ingestion, and returns the
  /// cassette.
  Future<Cassette> stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _ingestChain;
    return Cassette(entries: List.of(_entries));
  }
}

/// Serves a [Cassette] deterministically (spec 008): `loadUrl` matches an
/// entry (exact url, then path-prefix best match), serves its html via
/// the `loadHtml` port op, and synthesizes its captures on
/// [captureEvents] so downstream capture/distillation logic runs
/// unmodified — zero network.
class VcrReplayer {
  final Cassette cassette;
  final WebviewService service;
  final String webviewId;
  final bool strict;

  final _captures = StreamController<WebviewCaptureEntry>.broadcast();

  VcrReplayer({
    required this.cassette,
    required this.service,
    required this.webviewId,
    this.strict = true,
  });

  /// Synthesized capture events for every served entry (broadcast).
  Stream<WebviewCaptureEntry> get captureEvents => _captures.stream;

  /// Closes [captureEvents]; call when the replay is finished.
  Future<void> dispose() => _captures.close();

  /// Serves the best-matching entry for [url] offline.
  Future<void> loadUrl(String url) async {
    final entry = _bestMatch(url);
    if (entry == null) {
      if (strict) {
        throw WebviewException(
          'vcr_unmatched',
          'No cassette entry matches "$url" — record it before replaying.',
          recoverable: true,
        );
      }
      return;
    }
    await service.loadHtml(
      id: webviewId,
      html: entry.html,
      baseUrl: entry.url,
    );
    for (final capture in entry.captures) {
      _captures.add(capture);
    }
  }

  /// Exact url match first; otherwise the entry whose url is the longest
  /// path-prefix of the requested url (query-insensitive).
  CassetteEntry? _bestMatch(String url) {
    for (final e in cassette.entries) {
      if (e.url == url) return e;
    }
    final requested = Uri.tryParse(url);
    if (requested == null) return null;
    CassetteEntry? best;
    for (final e in cassette.entries) {
      final entryUri = Uri.tryParse(e.url);
      if (entryUri == null) continue;
      final sameOrigin =
          entryUri.scheme == requested.scheme && entryUri.host == requested.host;
      if (!sameOrigin) continue;
      if (requested.path.startsWith(entryUri.path) &&
          (best == null ||
              Uri.parse(best.url).path.length < entryUri.path.length)) {
        best = e;
      }
    }
    return best;
  }
}
