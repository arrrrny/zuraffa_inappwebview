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
  ///
  /// Returns null when `type` names no known phase: an unrecognised event
  /// is dropped rather than silently recorded as `started`, so a platform
  /// rename or typo cannot inject phantom visits into the record.
  static WebviewNavigationEvent? fromChannelArgs(
    Map<String, Object?> args, {
    DateTime? at,
  }) {
    final phase = phaseOf(args['type']);
    if (phase == null) return null;
    return WebviewNavigationEvent(
      phase: phase,
      url: args['url'] as String? ?? '',
      isMainFrame: args['isMainFrame'] as bool? ?? true,
      errorCode: args['code'] as String?,
      at: at,
    );
  }

  /// The phase named by a raw channel `type`, or null when unrecognised.
  static WebviewNavigationPhase? phaseOf(Object? raw) {
    for (final phase in WebviewNavigationPhase.values) {
      if (phase.name == raw) return phase;
    }
    return null;
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
  final Map<String, Object> _errors = {};

  NavigationTracker({
    this.dedupWindow = defaultDedupWindow,
    this.mainFrameOnly = true,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Records events from [events] under [id], replacing any previous
  /// subscription for that id. Cancel with [detach].
  ///
  /// The streams are specified to carry typed errors (`channel_not_wired`,
  /// `malformed_response`), so a handler is installed: without one they
  /// would surface as unhandled async errors. The last one is readable
  /// via [error].
  void attach(String id, Stream<WebviewNavigationEvent> events) {
    _subs[id]?.cancel();
    _errors.remove(id);
    _subs[id] = events.listen(
      (e) => handleEvent(id, e),
      onError: (Object error, StackTrace _) => _errors[id] = error,
    );
  }

  /// The last stream error observed for [id], if any.
  Object? error(String id) => _errors[id];

  /// Stops recording for [id] (keeps the record accumulated so far).
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Cancels every subscription (call when the tracker is done).
  void dispose() {
    for (final sub in _subs.values) {
      sub.cancel();
    }
    _subs.clear();
  }

  /// Drops the recorded visits for [id] (the sibling of
  /// `NetworkCaptureManager.clear`).
  void clear(String id) => _entries[id]?.clear();

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
  bool hasCycle(String id) {
    final urls = _entries[id]?.map((v) => v.url).toList() ?? const [];
    if (urls.length < 3) return false;
    final last = urls.last;
    return urls.take(urls.length - 1).contains(last);
  }
}
