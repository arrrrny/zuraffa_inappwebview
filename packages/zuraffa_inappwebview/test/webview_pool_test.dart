import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Fake port that counts create/run/dispose and can be asserted against.
class PoolFakePort implements WebviewPort {
  int creates = 0;
  int runs = 0;
  int disposes = 0;
  bool failRun = false;
  bool failCreate = false;
  final List<String> loadedUrls = [];

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async {
    creates++;
    if (failCreate) {
      throw const WebviewException('channel_error', 'create failed',
          recoverable: false);
    }
  }

  @override
  Future<void> runHeadless({required String id}) async {
    runs++;
    if (failRun) {
      throw const WebviewException('channel_error', 'run failed',
          recoverable: false);
    }
  }

  @override
  Future<void> disposeHeadless({required String id}) async => disposes++;

  @override
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) async =>
      loadedUrls.add(url.toString());

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
      const Stream.empty();

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

void main() {
  late PoolFakePort port;
  late WebviewService service;

  setUp(() {
    port = PoolFakePort();
    service = WebviewService(port: port);
  });

  group('US1 — session-scoped acquire', () {
    test('P1: same session -> same id, one create+run', () async {
      final pool = WebviewPool(service: service);
      final a = await pool.acquire('s1', domainHint: 'x.dev');
      final b = await pool.acquire('s1', domainHint: 'x.dev');
      expect(a, b);
      expect(port.creates, 1);
      expect(port.runs, 1);
      expect(pool.liveCount, 1);
      expect(pool.sessions(), {'s1'});
    });

    test('P2: release keeps the instance warm; session list updates',
        () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'x.dev');
      await pool.release('s1');
      expect(pool.sessions(), isEmpty);
      expect(pool.liveCount, 1); // warm idle instance still held
      expect(port.disposes, 0);
    });
  });

  group('US2 — domain affinity', () {
    test('P3: same eTLD+1 idle instance is reused after a reset', () async {
      final pool = WebviewPool(service: service);
      final first = await pool.acquire('s1', domainHint: 'x.dev');
      await pool.release('s1');
      port.loadedUrls.clear();
      final second = await pool.acquire('s2', domainHint: 'shop.x.dev');
      expect(second, first);
      expect(port.creates, 1);
      // The previous mission's document must not leak into the new one.
      expect(port.loadedUrls, ['about:blank']);
    });

    test('P4: different domain does not reuse', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'x.dev');
      await pool.release('s1');
      await pool.acquire('s2', domainHint: 'other.dev');
      expect(port.creates, 2);
    });
  });

  group('US3 — caps + eviction', () {
    test('P5a: maxLive evicts the idlest instance first', () async {
      final pool = WebviewPool(service: service, maxLive: 2);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.release('s1');
      await pool.acquire('s2', domainHint: 'b.dev');
      // pool now holds idle(a.dev) + active(b.dev) = 2 = maxLive
      await pool.acquire('s3', domainHint: 'c.dev');
      expect(port.disposes, 1); // the idle a.dev instance was evicted
      expect(pool.liveCount, 2);
    });

    test('P5b: saturated pool -> typed pool_exhausted', () async {
      final pool = WebviewPool(service: service, maxLive: 1);
      await pool.acquire('s1', domainHint: 'a.dev');
      await expectLater(
        pool.acquire('s2', domainHint: 'b.dev'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'pool_exhausted')),
      );
    });

    test('P6: idleTtl sweep disposes stale idles (injected clock)',
        () async {
      var now = DateTime(2026, 1, 1);
      final pool = WebviewPool(
        service: service,
        idleTtl: const Duration(minutes: 2),
        clock: () => now,
      );
      final first = await pool.acquire('s1', domainHint: 'a.dev');
      await pool.release('s1');
      now = now.add(const Duration(minutes: 3));
      final second = await pool.acquire('s2', domainHint: 'a.dev');
      expect(second, isNot(first));
      expect(port.disposes, 1);
    });
  });

  group('US4 — disposeAll', () {
    test('P7: everything disposed, counts zero', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.acquire('s2', domainHint: 'b.dev');
      await pool.release('s2');
      await pool.disposeAll();
      expect(pool.liveCount, 0);
      expect(pool.sessions(), isEmpty);
      expect(port.disposes, 2);
      expect(service.created, isEmpty);
    });
  });

  group('US3 — per-domain cap', () {
    test('P8a: an idle same-domain instance is reused, not capped out',
        () async {
      final pool = WebviewPool(service: service, maxPerDomain: 2);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.release('s1');
      final reused = await pool.acquire('s2', domainHint: 'a.dev');
      expect(reused, isNotNull);
      expect(port.creates, 1);
    });

    test('P8b: a third live instance on one domain -> typed '
        'pool_exhausted with free maxLive slots', () async {
      final pool = WebviewPool(service: service, maxPerDomain: 2);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.acquire('s2', domainHint: 'a.dev');
      await expectLater(
        pool.acquire('s3', domainHint: 'a.dev'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'pool_exhausted')),
      );
      expect(pool.liveCount, 2);
      expect(port.creates, 2);
    });

    test('P8c: releasing one session frees a per-domain slot', () async {
      final pool = WebviewPool(service: service, maxPerDomain: 2);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.acquire('s2', domainHint: 'a.dev');
      await pool.release('s1');
      await pool.acquire('s3', domainHint: 'a.dev');
      expect(pool.sessions(), {'s2', 's3'});
      expect(port.creates, 2);
    });

    test('P8d: another domain is unaffected by the cap', () async {
      final pool = WebviewPool(service: service, maxPerDomain: 2);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.acquire('s2', domainHint: 'a.dev');
      await pool.acquire('s3', domainHint: 'b.dev');
      expect(port.creates, 3);
    });
  });

  group('US5 — concurrency + failure cleanup', () {
    test('P9: overlapping acquires for one session create one instance',
        () async {
      final pool = WebviewPool(service: service);
      final ids = await Future.wait([
        pool.acquire('s1', domainHint: 'a.dev'),
        pool.acquire('s1', domainHint: 'a.dev'),
        pool.acquire('s1', domainHint: 'a.dev'),
      ]);
      expect(ids.toSet(), hasLength(1));
      expect(port.creates, 1);
      expect(port.runs, 1);
      expect(pool.liveCount, 1);
    });

    test('P10: overlapping acquires cannot overshoot maxLive', () async {
      final pool = WebviewPool(service: service, maxLive: 2);
      final results = await Future.wait([
        pool.acquire('s1', domainHint: 'a.dev'),
        pool.acquire('s2', domainHint: 'b.dev'),
        pool.acquire('s3', domainHint: 'c.dev'),
        pool.acquire('s4', domainHint: 'd.dev'),
      ].map((f) => f.then<Object?>((v) => v, onError: (Object e) => e)));
      expect(pool.liveCount, 2);
      expect(results.whereType<WebviewException>(), hasLength(2));
      expect(port.creates, 2);
    });

    test('P11: a runHeadless failure disposes the created webview',
        () async {
      port.failRun = true;
      final pool = WebviewPool(service: service);
      await expectLater(
        pool.acquire('s1', domainHint: 'a.dev'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'channel_error')),
      );
      expect(pool.liveCount, 0);
      expect(pool.hasSession('s1'), isFalse);
      expect(port.disposes, 1);
      expect(service.created, isEmpty);
    });

    test('P12: release on an unknown session is a no-op', () async {
      final pool = WebviewPool(service: service);
      await pool.release('nope');
      expect(pool.liveCount, 0);
      expect(port.disposes, 0);
    });

    test('P13: hasSession tracks acquire and release', () async {
      final pool = WebviewPool(service: service);
      expect(pool.hasSession('s1'), isFalse);
      await pool.acquire('s1', domainHint: 'a.dev');
      expect(pool.hasSession('s1'), isTrue);
      await pool.release('s1');
      expect(pool.hasSession('s1'), isFalse);
    });
  });
}
