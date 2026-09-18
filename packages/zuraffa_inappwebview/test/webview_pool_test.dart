import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Fake port that counts create/run/dispose and can be asserted against.
class PoolFakePort implements WebviewPort {
  int creates = 0;
  int runs = 0;
  int disposes = 0;
  Object? runError;
  Object? disposeError;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async =>
      creates++;

  @override
  Future<void> runHeadless({required String id}) async {
    runs++;
    final error = runError;
    if (error != null) throw error;
  }

  @override
  Future<void> disposeHeadless({required String id}) async {
    disposes++;
    final error = disposeError;
    if (error != null) throw error;
  }

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
      const Stream.empty();

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
    test('P3: same eTLD+1 idle instance is reused', () async {
      final pool = WebviewPool(service: service);
      final first = await pool.acquire('s1', domainHint: 'x.dev');
      await pool.release('s1');
      final second = await pool.acquire('s2', domainHint: 'shop.x.dev');
      expect(second, first);
      expect(port.creates, 1);
    });

    test('P4: different domain does not reuse', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'x.dev');
      await pool.release('s1');
      await pool.acquire('s2', domainHint: 'other.dev');
      expect(port.creates, 2);
    });

    test('P4b: IP literals are their own domain', () async {
      expect(WebviewPool.registrableDomain('10.0.0.5'), '10.0.0.5');
      expect(WebviewPool.registrableDomain('192.168.0.5'), '192.168.0.5');
      expect(WebviewPool.registrableDomain('::1'), '::1');

      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: '10.0.0.5');
      await pool.release('s1');
      await pool.acquire('s2', domainHint: '192.168.0.5');
      expect(port.creates, 2); // no cross-host reuse
    });
  });

  group('US3 — caps + eviction', () {
    test('P5a: maxLive evicts the idlest instance first', () async {
      var now = DateTime(2026, 1, 1);
      final pool = WebviewPool(service: service, maxLive: 2, clock: () => now);
      final first = await pool.acquire('s1', domainHint: 'a.dev');
      await pool.release('s1');
      now = now.add(const Duration(minutes: 1));
      final second = await pool.acquire('s2', domainHint: 'b.dev');
      await pool.release('s2');
      // two warm idles, distinct idleSince: a.dev is the older one
      final third = await pool.acquire('s3', domainHint: 'c.dev');
      expect(port.disposes, 1);
      expect(pool.liveCount, 2);
      expect(service.created, isNot(contains(first))); // the idlest went
      expect(service.created, contains(second));
      expect(service.created, contains(third));
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

    test('P5c: per-domain cap -> pool_exhausted', () async {
      final pool = WebviewPool(service: service, maxPerDomain: 1);
      await pool.acquire('s1', domainHint: 'x.dev');
      await expectLater(
        pool.acquire('s2', domainHint: 'shop.x.dev'), // same eTLD+1
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'pool_exhausted')),
      );
      expect(port.creates, 1);
    });

    test('P5d: a warm same-domain instance is reused, not evicted', () async {
      final pool = WebviewPool(service: service, maxPerDomain: 1);
      final first = await pool.acquire('s1', domainHint: 'x.dev');
      await pool.release('s1');
      final second = await pool.acquire('s2', domainHint: 'shop.x.dev');
      expect(second, first);
      expect(port.creates, 1);
      expect(port.disposes, 0);
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

    test('P8: a failed runHeadless disposes the created webview', () async {
      port.runError = const WebviewException(
        'run_failed',
        'boom',
        recoverable: true,
      );
      final pool = WebviewPool(service: service);
      await expectLater(
        pool.acquire('s1', domainHint: 'a.dev'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'run_failed')),
      );
      expect(port.creates, 1);
      expect(port.disposes, 1);
      expect(pool.liveCount, 0);
      expect(service.created, isEmpty);
    });

    test('P9: a failed dispose keeps the instance retryable', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'a.dev');
      port.disposeError = const WebviewException(
        'dispose_failed',
        'boom',
        recoverable: true,
      );
      await expectLater(
        pool.disposeAll(),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'dispose_failed')),
      );
      expect(pool.liveCount, 1); // still reachable: the service still knows it
      expect(service.created, {'pool-1'});

      port.disposeError = null;
      await pool.disposeAll();
      expect(pool.liveCount, 0);
      expect(service.created, isEmpty);
    });

    test('P9b: disposeAll attempts every instance before surfacing the error',
        () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.acquire('s2', domainHint: 'b.dev');
      port.disposeError = const WebviewException(
        'dispose_failed',
        'boom',
        recoverable: true,
      );
      await expectLater(pool.disposeAll(), throwsA(isA<WebviewException>()));
      expect(port.disposes, 2); // the second was attempted, not skipped
    });
  });
}
