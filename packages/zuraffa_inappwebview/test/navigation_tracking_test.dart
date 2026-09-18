import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

void main() {
  group('US1 — codec', () {
    test('N1: decodes completed with defaults', () {
      final e = WebviewNavigationEvent.fromChannelArgs(const {
        'type': 'completed',
        'url': 'https://x.dev/',
      });
      expect(e.phase, WebviewNavigationPhase.completed);
      expect(e.url, 'https://x.dev/');
      expect(e.isMainFrame, isTrue);
      expect(e.errorCode, isNull);
    });

    test('N1: decodes failed with error code + sub-frame flag', () {
      final e = WebviewNavigationEvent.fromChannelArgs(const {
        'type': 'failed',
        'url': 'https://x.dev/',
        'isMainFrame': false,
        'code': 'net_err',
      });
      expect(e.phase, WebviewNavigationPhase.failed);
      expect(e.isMainFrame, isFalse);
      expect(e.errorCode, 'net_err');
    });

    test('N1: an unknown phase type is a typed malformed_response', () {
      expect(
        () => WebviewNavigationEvent.fromChannelArgs(const {
          'type': 'didFinish',
          'url': 'https://x.dev/',
        }),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'malformed_response')
            .having((e) => e.recoverable, 'recoverable', isFalse)),
      );
    });
  });

  group('US1 — service stream', () {
    late StreamController<WebviewNavigationEvent> controller;
    late _StreamFakePort port;
    late WebviewService service;

    setUp(() async {
      controller = StreamController<WebviewNavigationEvent>.broadcast();
      port = _StreamFakePort(controller.stream);
      service = WebviewService(port: port);
      await service.createHeadless(id: 'w');
    });

    tearDown(() => controller.close());

    test('N2: passthrough streams typed events', () async {
      final events = <WebviewNavigationEvent>[];
      final sub = service.navigationEvents(id: 'w').listen(events.add);
      controller.add(
        WebviewNavigationEvent.fromChannelArgs(
            const {'type': 'started', 'url': 'https://x.dev/'}),
      );
      await pump();
      expect(events, hasLength(1));
      expect(events.single.url, 'https://x.dev/');
      await sub.cancel();
    });

    test('N2: unknown id -> not_created', () {
      expect(
        () => service.navigationEvents(id: 'nope'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'not_created')),
      );
    });

    test('N2: unwired -> port_not_wired', () {
      expect(
        () => const UnwiredWebviewPort().navigationEvents(id: 'w'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'port_not_wired')),
      );
    });
  });

  group('US2 — tracker', () {
    test('N3: ordered entries + lastUrl', () {
      final tracker = NavigationTracker();
      tracker.handleEvent(
          'w', _ev(WebviewNavigationPhase.started, 'https://a.dev/'));
      tracker.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      tracker.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://b.dev/'));
      expect(
        tracker.entries('w').map((v) => '${v.phase.name}:${v.url}'),
        [
          'started:https://a.dev/',
          'completed:https://a.dev/',
          'completed:https://b.dev/',
        ],
      );
      expect(tracker.lastUrl('w'), 'https://b.dev/');
      expect(tracker.entries('other'), isEmpty);
    });

    test('N4: dedup window collapses same-url repeats (earliest kept)',
        () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final tracker = NavigationTracker(clock: () => now);
      tracker.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      now = now.add(const Duration(milliseconds: 200));
      tracker.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      expect(tracker.entries('w'), hasLength(1));
      now = now.add(const Duration(milliseconds: 600));
      tracker.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      expect(tracker.entries('w'), hasLength(2));
    });

    test('N5: mainFrameOnly drops sub-frame events by default', () {
      WebviewNavigationEvent subFrame(String url) =>
          WebviewNavigationEvent.fromChannelArgs(
              {'type': 'completed', 'url': url, 'isMainFrame': false});
      final tracker = NavigationTracker();
      tracker.handleEvent('w', subFrame('https://a.dev/frame'));
      expect(tracker.entries('w'), isEmpty);
      final loose = NavigationTracker(mainFrameOnly: false);
      loose.handleEvent('w', subFrame('https://a.dev/frame'));
      expect(loose.entries('w'), hasLength(1));
    });

    test('N6: hasCycle + detach', () async {
      final controller = StreamController<WebviewNavigationEvent>();
      final tracker = NavigationTracker();
      tracker.attach('w', controller.stream);
      controller.add(
          _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      controller.add(
          _ev(WebviewNavigationPhase.completed, 'https://b.dev/'));
      controller.add(
          _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      await pump();
      expect(tracker.hasCycle('w'), isTrue);

      final linear = NavigationTracker();
      linear.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://a.dev/'));
      linear.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://b.dev/'));
      linear.handleEvent(
          'w', _ev(WebviewNavigationPhase.completed, 'https://c.dev/'));
      expect(linear.hasCycle('w'), isFalse);

      tracker.detach('w');
      final before = tracker.entries('w').length;
      controller.add(
          _ev(WebviewNavigationPhase.completed, 'https://d.dev/'));
      await pump();
      expect(tracker.entries('w').length, before);
      await controller.close();
    });
  });
}

WebviewNavigationEvent _ev(WebviewNavigationPhase phase, String url) =>
    WebviewNavigationEvent.fromChannelArgs({
      'type': phase.name,
      'url': url,
    });

Future<void> pump() => Future<void>.delayed(Duration.zero);

class _StreamFakePort implements WebviewPort {
  final Stream<WebviewNavigationEvent> events;

  _StreamFakePort(this.events);

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async {}

  @override
  Future<void> runHeadless({required String id}) async {}

  @override
  Future<void> disposeHeadless({required String id}) async {}

  @override
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) async {}

  @override
  Future<String?> currentUrl({required String id}) async => null;

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async =>
      null;

  @override
  Future<String?> getHtml({required String id}) async => null;

  @override
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) async =>
      null;

  @override
  Future<List<int>?> exportPdf({required String id}) async => null;

  @override
  Stream<WebviewNavigationEvent> navigationEvents({required String id}) =>
      events;

  @override
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) async {}

  @override
  Future<void> setCaptureEnabled({
    required String id,
    required bool enabled,
    WebviewCaptureFilter? filter,
  }) async {}

  @override
  Stream<WebviewCaptureEntry> captureEvents({required String id}) =>
      const Stream.empty();
  @override
  Future<void> setCookie(WebviewCookie cookie) async {}

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) async => [];

  @override
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) async =>
      false;

  @override
  Future<void> deleteAllCookies() async {}
}
