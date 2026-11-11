/// Navigation tracking (spec 004): typed navigation events + the ordered,
/// deduplicated URL-cycle record per webview.
library;

import 'dart:async';

/// The phase of a navigation event (channel key `type`).
enum WebviewNavigationPhase { started, completed, failed }

/// One navigation observation pushed by the platform for a webview.
class WebviewNavigationEvent {
  final WebviewNavigationPhase phase;
  final String url;
  final bool isMainFrame;
  final String? errorCode;
  final DateTime at;

  WebviewNavigationEvent({
    required this.phase,
    required this.url,
    this.isMainFrame = true,
    this.errorCode,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// Codec from channel args: `type`, `url`, `isMainFrame` (default true),
  /// `code` (optional).
  static WebviewNavigationEvent fromChannelArgs(
    Map<String, Object?> args, {
    DateTime? at,
  }) =>
      WebviewNavigationEvent(
        phase: WebviewNavigationPhase.values.firstWhere(
          (p) => p.name == args['type'],
          orElse: () => WebviewNavigationPhase.started,
        ),
        url: args['url'] is String ? args['url'] as String : '',
        isMainFrame: switch (args['isMainFrame']) {
          bool v => v,
          num v => v != 0,
          _ => true,
        },
        errorCode: args['code'] is String ? args['code'] as String : null,
        at: at,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebviewNavigationEvent &&
          other.phase == phase &&
          other.url == url &&
          other.isMainFrame == isMainFrame &&
          other.errorCode == errorCode;

  @override
  int get hashCode => Object.hash(phase, url, isMainFrame, errorCode);
}

/// One recorded visit in a webview's URL-cycle history.
class UrlVisit {
  final WebviewNavigationPhase phase;
  final String url;
  final DateTime at;
  final String? errorCode;

  const UrlVisit({
    required this.phase,
    required this.url,
    required this.at,
    this.errorCode,
  });
}

/// Ordered, deduplicated URL-cycle record per webview id (spec 004).
///
/// - Dedup rule: a transition (phase + url) repeating within
///   [dedupWindow] collapses to its earliest occurrence.
/// - `mainFrameOnly` (default) drops sub-frame events.
/// - [hasCycle] reports a revisit loop (A → B → A) over the record.
///
/// Works without a webview: [handleEvent] operates on a plain instance;
/// [attach] wires a webview's event stream.
class NavigationTracker {
  static const Duration defaultDedupWindow = Duration(milliseconds: 500);

  final Duration dedupWindow;
  final bool mainFrameOnly;
  final DateTime Function() clock;

  final Map<String, List<UrlVisit>> _entries = {};
  final Map<String, StreamSubscription<WebviewNavigationEvent>> _subs = {};

  NavigationTracker({
    this.dedupWindow = defaultDedupWindow,
    this.mainFrameOnly = true,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Records events from [events] under [id], replacing any previous
  /// subscription for that id. Cancel with [detach].
  void attach(String id, Stream<WebviewNavigationEvent> events) {
    _subs[id]?.cancel();
    _subs[id] = events.listen((e) => handleEvent(id, e));
  }

  /// Stops recording for [id] (keeps the record accumulated so far).
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Records one event. Pure — no webview required. Timing authority is
  /// the tracker's [clock] — platform event timestamps are informational.
  void handleEvent(String id, WebviewNavigationEvent event) {
    if (mainFrameOnly && !event.isMainFrame) return;
    final visits = _entries.putIfAbsent(id, () => []);
    final now = clock();
    final last = visits.isEmpty ? null : visits.last;
    if (last != null &&
        last.phase == event.phase &&
        last.url == event.url &&
        now.difference(last.at) <= dedupWindow) {
      return;
    }
    visits.add(UrlVisit(
      phase: event.phase,
      url: event.url,
      at: now,
      errorCode: event.errorCode,
    ));
  }

  /// The recorded visits for [id], in order (unmodifiable).
  List<UrlVisit> entries(String id) =>
      List.unmodifiable(_entries[id] ?? const []);

  /// The url of the most recent recorded visit, or null when empty.
  String? lastUrl(String id) =>
      (_entries[id]?.isEmpty ?? true) ? null : _entries[id]!.last.url;

  /// Whether the record shows a revisit loop: the latest url reappears
  /// earlier in the record (A → B → A).
  ///
  /// Only `completed` visits count, and consecutive repeats of one url
  /// collapse. Adapters emit a `started`+`completed` pair per load, so
  /// reading the raw entries would make every ordinary two-page browse
  /// look like a loop.
  bool hasCycle(String id) {
    final urls = <String>[];
    for (final v in _entries[id] ?? const <UrlVisit>[]) {
      if (v.phase != WebviewNavigationPhase.completed) continue;
      if (urls.isEmpty || urls.last != v.url) urls.add(v.url);
    }
    if (urls.length < 3) return false;
    return urls.take(urls.length - 1).contains(urls.last);
  }
}
