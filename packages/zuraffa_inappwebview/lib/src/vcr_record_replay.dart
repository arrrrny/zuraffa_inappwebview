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
        'at': c.at.toIso8601String(),
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

  /// Reads a cassette with a missing `formatVersion` as the current
  /// format, and refuses an unsupported one: versioning only means
  /// something if a reader can reject a file it cannot interpret.
  static Cassette fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'] as int? ?? currentFormatVersion;
    if (version != currentFormatVersion) {
      throw WebviewException(
        'vcr_unsupported_format',
        'Cassette format v$version is not supported (this build reads '
        'v$currentFormatVersion).',
        recoverable: false,
      );
    }
    return Cassette(
      formatVersion: version,
      entries: [
        for (final e in (json['entries'] as List? ?? const []))
          CassetteEntry.fromJson(Map<String, Object?>.from(e as Map)),
      ],
    );
  }
}

/// Records a live session into a [Cassette] (spec 008). Watches the
/// webview's navigation + capture streams; each completed main-frame
/// navigation freezes an entry with html/cookie snapshots and the
/// captures observed since the previous navigation. Capture payloads are
/// defensively re-redacted (the 005 redactor).
///
/// Capture ownership is decided when the navigation event arrives: the
/// pending captures are snapshotted and cleared synchronously at that
/// point, and the html/cookie freeze that follows is single-flight in
/// event order. A capture arriving *during* a freeze therefore belongs to
/// the next navigation — it is never misattributed to the entry being
/// frozen, and never dropped.
class VcrRecorder {
  final WebviewService service;
  final String webviewId;
  final CaptureSecretRedactor _redactor = const CaptureSecretRedactor();

  final List<CassetteEntry> _entries = [];
  final List<WebviewCaptureEntry> _pendingCaptures = [];
  final List<StreamSubscription> _subs = [];

  /// Tail of the single-flight freeze queue.
  Future<void> _queue = Future<void>.value();

  VcrRecorder({required this.service, required this.webviewId});

  /// Starts watching [navigationEvents] and [captureEvents].
  void record({
    required Stream<WebviewNavigationEvent> navigationEvents,
    required Stream<WebviewCaptureEntry> captureEvents,
  }) {
    _subs.add(captureEvents.listen(ingestCapture));
    _subs.add(navigationEvents.listen(ingestNavigation));
  }

  /// Buffers one capture (redacted defensively) for the next entry.
  void ingestCapture(WebviewCaptureEntry entry) =>
      _pendingCaptures.add(_redactor.redact(entry));

  /// Freezes an entry for a completed main-frame navigation.
  ///
  /// The pending-capture snapshot and clear are synchronous with the event;
  /// only the html/cookie freeze is asynchronous, and it is queued so
  /// entries follow event order rather than await-resolution order.
  Future<void> ingestNavigation(WebviewNavigationEvent event) {
    if (event.phase != WebviewNavigationPhase.completed ||
        !event.isMainFrame) {
      return Future<void>.value();
    }
    final captures = List.of(_pendingCaptures);
    _pendingCaptures.clear();
    final frozen = _queue.then((_) => _freeze(event, captures));
    _queue = frozen.catchError((Object _) {});
    return frozen;
  }

  Future<void> _freeze(
    WebviewNavigationEvent event,
    List<WebviewCaptureEntry> captures,
  ) async {
    final html = await service.getHtml(id: webviewId) ?? '';
    final cookies = await service.getCookies(url: event.url);
    _entries.add(CassetteEntry(
      url: event.url,
      html: html,
      cookies: List.of(cookies),
      captures: captures,
    ));
  }

  /// Stops watching and returns the cassette, waiting for any in-flight
  /// freeze so nothing observed is missing from it.
  Future<Cassette> stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _queue;
    return Cassette(entries: List.of(_entries));
  }
}

/// Serves a [Cassette] deterministically (spec 008): `loadUrl` matches an
/// entry (exact url, then path-prefix best match), serves its html via
/// the `loadHtml` port op, and synthesizes its captures on
/// [captureEvents] so downstream capture/distillation logic runs
/// unmodified — zero network.
///
/// Limitation: replay restores html and captures only. [CassetteEntry.cookies]
/// is recorded and JSON round-tripped, but nothing here writes it back —
/// `loadHtml` renders through the platform's *shared* cookie store and no
/// `setCookie` restore is issued, so a replay is deterministic in served
/// content, not in cookie state.
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
  /// Closed by [dispose].
  Stream<WebviewCaptureEntry> get captureEvents => _captures.stream;

  /// Closes the synthesized capture stream. Call when done replaying — a
  /// consumer that awaits completion (`toList`, `firstWhere`) would
  /// otherwise never see a done event.
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

  /// Exact url match first; otherwise the longest same-origin entry whose
  /// path is a prefix of the requested path **ending on a path-segment
  /// boundary** (`/a` matches `/a` and `/a/page/2`, never `/abc`). The
  /// query is not part of the comparison; the port is.
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
      final sameOrigin = entryUri.scheme == requested.scheme &&
          entryUri.host == requested.host &&
          entryUri.port == requested.port;
      if (!sameOrigin) continue;
      final boundary = entryUri.path.endsWith('/')
          ? entryUri.path
          : '${entryUri.path}/';
      final matchesPath = requested.path == entryUri.path ||
          requested.path.startsWith(boundary);
      if (matchesPath &&
          (best == null ||
              Uri.parse(best.url).path.length < entryUri.path.length)) {
        best = e;
      }
    }
    return best;
  }
}
