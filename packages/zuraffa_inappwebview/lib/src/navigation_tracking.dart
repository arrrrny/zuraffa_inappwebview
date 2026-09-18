/// Navigation tracking (spec 004): typed navigation events + the ordered,
/// deduplicated URL-cycle record per webview.
library;

import 'dart:async';

import 'webview_exception.dart';

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
  /// `code` (optional). An unrecognized `type` is a typed
  /// `malformed_response` failure rather than a silent `started`: the
  /// phase enum has no unknown member for a caller to defend against.
  static WebviewNavigationEvent fromChannelArgs(
    Map<String, Object?> args, {
    DateTime? at,
  }) {
    final raw = args['type'];
    final phase = WebviewNavigationPhase.values
        .where((p) => p.name == raw)
        .firstOrNull;
    if (phase == null) {
      throw WebviewException(
        'malformed_response',
        'Unknown navigation phase "$raw".',
        recoverable: false,
      );
    }
    return WebviewNavigationEvent(
      phase: phase,
      url: args['url'] as String? ?? '',
      isMainFrame: args['isMainFrame'] as bool? ?? true,
      errorCode: args['code'] as String?,
      at: at,
    );
  }

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
/// - Dedup rule: a (phase + url) transition repeating *immediately after
///   the preceding visit* within [dedupWindow] collapses into that visit.
///   The scope is adjacency, not the whole window: a url that repeats
///   after any intervening transition is recorded again.
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
  /// anywhere earlier in the record (A → B → A). Consecutive repeats
  /// count too, so A → A → A reports a cycle.
  bool hasCycle(String id) {
    final urls = _entries[id]?.map((v) => v.url).toList() ?? const [];
    if (urls.length < 3) return false;
    final last = urls.last;
    return urls.take(urls.length - 1).contains(last);
  }
}
