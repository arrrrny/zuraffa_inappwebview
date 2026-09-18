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
class Cassette {
  static const int currentFormatVersion = 1;

  final int formatVersion;
  final List<CassetteEntry> entries;

  const Cassette({this.formatVersion = currentFormatVersion, this.entries = const []});

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'entries': [for (final e in entries) e.toJson()],
      };

  static Cassette fromJson(Map<String, Object?> json) => Cassette(
        formatVersion:
            json['formatVersion'] as int? ?? currentFormatVersion,
        entries: [
          for (final e in (json['entries'] as List? ?? const []))
            CassetteEntry.fromJson(Map<String, Object?>.from(e as Map)),
        ],
      );
}

/// Records a live session into a [Cassette] (spec 008). Watches the
/// webview's navigation + capture streams; each completed main-frame
/// navigation freezes an entry with html/cookie snapshots and the
/// captures observed since the previous navigation. Capture payloads are
/// defensively re-redacted (the 005 redactor).
///
/// [stop] awaits navigation handlers that are still mid-flight, so a
/// navigation that arrived just before the caller stopped recording is
/// still in the cassette.
class VcrRecorder {
  final WebviewService service;
  final String webviewId;
  final CaptureSecretRedactor _redactor = const CaptureSecretRedactor();

  final List<CassetteEntry> _entries = [];
  final List<WebviewCaptureEntry> _pendingCaptures = [];
  final List<StreamSubscription> _subs = [];
  final Set<Future<void>> _inFlight = {};

  VcrRecorder({required this.service, required this.webviewId});

  /// Starts watching [navigationEvents] and [captureEvents].
  void record({
    required Stream<WebviewNavigationEvent> navigationEvents,
    required Stream<WebviewCaptureEntry> captureEvents,
  }) {
    _subs.add(captureEvents.listen(ingestCapture));
    _subs.add(navigationEvents.listen(_trackNavigation));
  }

  /// Listens for a navigation without blocking the stream, keeping the
  /// handler's future so [stop] can wait for it.
  void _trackNavigation(WebviewNavigationEvent event) {
    final pending = ingestNavigation(event);
    _inFlight.add(pending);
    unawaited(pending.whenComplete(() => _inFlight.remove(pending)));
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

  /// Stops watching and returns the cassette.
  ///
  /// Cancelling the subscriptions is not enough on its own: a handler
  /// already running ([ingestNavigation] awaits `getHtml`, then
  /// `getCookies`) would finish after the snapshot and lose its entry.
  Future<Cassette> stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    if (_inFlight.isNotEmpty) {
      await Future.wait([
        for (final pending in _inFlight) pending.catchError((Object _) {}),
      ]);
    }
    return Cassette(entries: List.of(_entries));
  }
}

/// Serves a [Cassette] deterministically (spec 008): `loadUrl` matches an
/// entry (exact url, then path-prefix best match), serves its html via
/// the `loadHtml` port op, and synthesizes its captures on
/// [captureEvents] so downstream capture/distillation logic runs
/// unmodified — zero network.
///
/// Call [dispose] alongside disposing the webview it serves: it closes
/// the synthesized-capture stream, so a consumer awaiting
/// `captureEvents.done` completes instead of waiting for the life of the
/// process.
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

  /// Closes [captureEvents]; the replayer serves nothing afterwards.
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
