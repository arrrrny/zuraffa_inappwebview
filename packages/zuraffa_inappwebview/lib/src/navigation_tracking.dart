/// Navigation tracking (spec 004): typed navigation events + the ordered,
/// deduplicated URL-cycle record per webview.
library;

import 'dart:async';

/// The phase of a navigation event (channel key `type`).
///
/// [unknown] is the explicit bucket for a phase this client does not know
/// (a forward-compat native rename or a new phase): the record surfaces the
/// gap instead of mislabelling the event as a navigation.
enum WebviewNavigationPhase { started, completed, failed, unknown }

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
  /// `code` (optional). An unrecognised `type` decodes to
  /// [WebviewNavigationPhase.unknown] — the record never claims a
  /// navigation the platform did not report.
  static WebviewNavigationEvent fromChannelArgs(
    Map<String, Object?> args, {
    DateTime? at,
  }) =>
      WebviewNavigationEvent(
        phase: WebviewNavigationPhase.values.firstWhere(
          (p) => p.name == args['type'],
          orElse: () => WebviewNavigationPhase.unknown,
        ),
        url: args['url'] as String? ?? '',
        isMainFrame: args['isMainFrame'] as bool? ?? true,
        errorCode: args['code'] as String?,
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
  ///
  /// Adapter streams surface typed data-plane errors by contract
  /// (`malformed_response`, `channel_not_wired`); they are contained here so
  /// one bad native payload never becomes an unhandled async error in the
  /// consumer's zone. A caller that subscribes to a stream manually must
  /// pass its own `onError`.
  void attach(String id, Stream<WebviewNavigationEvent> events) {
    _subs[id]?.cancel();
    _subs[id] = events.listen(
      (e) => handleEvent(id, e),
      onError: (Object error) {
        // Contained: a stream error is data-plane noise, not a reason to
        // tear down the consumer's zone.
        assert(() {
          // ignore: avoid_print
          print('NavigationTracker: navigation stream error for $id: $error');
          return true;
        }());
      },
    );
  }

  /// Stops recording for [id] (keeps the record accumulated so far); use
  /// [clear] to also drop the record.
  void detach(String id) {
    _subs.remove(id)?.cancel();
  }

  /// Drops every recorded visit for [id].
  void clear(String id) => _entries.remove(id);

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
