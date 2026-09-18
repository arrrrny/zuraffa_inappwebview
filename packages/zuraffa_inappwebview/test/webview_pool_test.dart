import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Fake port that counts create/run/dispose and can be asserted against.
class PoolFakePort implements WebviewPort {
  int creates = 0;
  int runs = 0;
  int disposes = 0;
  int disposeAttempts = 0;

  /// The ids the pool successfully disposed, in order.
  final List<String> disposed = [];

  /// Native-failure switches for the pool's failure paths.
  bool failRun = false;
  bool failDispose = false;

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
    if (failRun) {
      throw const WebviewException('channel_error', 'run failed',
          recoverable: true);
    }
    runs++;
  }

  @override
  Future<void> disposeHeadless({required String id}) async {
    disposeAttempts++;
    if (failDispose) {
      throw const WebviewException('channel_error', 'dispose failed',
          recoverable: true);
    }
    disposes++;
    disposed.add(id);
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

    test('P1b: concurrent acquires for one session share one instance',
        () async {
      final pool = WebviewPool(service: service);
      final ids = await Future.wait([
        pool.acquire('s1', domainHint: 'x.dev'),
        pool.acquire('s1', domainHint: 'x.dev'),
      ]);
      expect(ids, ['pool-1', 'pool-1']);
      expect(port.creates, 1);
      expect(port.runs, 1);
      expect(pool.liveCount, 1);
      await pool.release('s1');
      // The release is wholly applied: no stranded second instance.
      expect(pool.sessions(), isEmpty);
      expect(pool.liveCount, 1);
    });

    test('P1c: a failed runHeadless disposes the created webview', () async {
      port.failRun = true;
      final pool = WebviewPool(service: service);
      await expectLater(
        pool.acquire('s1', domainHint: 'x.dev'),
        throwsA(isA<WebviewException>()),
      );
      expect(port.disposes, 1);
      expect(pool.liveCount, 0);
      expect(pool.sessions(), isEmpty);
      expect(service.created, isEmpty); // nothing orphaned on the service
      // The failure does not poison the session for later acquires.
      port.failRun = false;
      expect(await pool.acquire('s1', domainHint: 'x.dev'), 'pool-2');
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

    test('P3b: registrableDomain normalizes case, ports and URLs', () {
      expect(WebviewPool.registrableDomain('shop.x.dev'), 'x.dev');
      expect(WebviewPool.registrableDomain('Shop.X.DEV'), 'x.dev');
      expect(WebviewPool.registrableDomain('  x.dev  '), 'x.dev');
      expect(WebviewPool.registrableDomain('shop.x.dev:8443'), 'x.dev');
      expect(
        WebviewPool.registrableDomain('https://shop.x.dev/cart?q=1#top'),
        'x.dev',
      );
    });

    test('P3c: IP literals and single labels map to themselves', () {
      expect(WebviewPool.registrableDomain('192.168.1.10'), '192.168.1.10');
      expect(WebviewPool.registrableDomain('10.0.1.10'), '10.0.1.10');
      expect(WebviewPool.registrableDomain('localhost'), 'localhost');
    });

    test('P3d: unrelated IP hosts never share an idle webview', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: '192.168.1.10');
      await pool.release('s1');
      await pool.acquire('s2', domainHint: '10.0.1.10');
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

    test('P5a: maxLive evicts the older idle of two', () async {
      var now = DateTime(2026, 1, 1);
      final pool = WebviewPool(
        service: service,
        maxLive: 2,
        clock: () => now,
      );
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.release('s1'); // idle since t0 — the older idle
      now = now.add(const Duration(seconds: 30));
      await pool.acquire('s2', domainHint: 'b.dev');
      await pool.release('s2'); // idle since t0+30 — the newer idle
      now = now.add(const Duration(seconds: 30));
      await pool.acquire('s3', domainHint: 'c.dev');
      expect(port.disposes, 1);
      expect(port.disposed, ['pool-1']); // older idle, not the newest
      expect(pool.liveCount, 2);
      expect(pool.sessions(), {'s3'});
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

    test('P5c: a domain at cap evicts its own idle instance', () async {
      final pool = WebviewPool(service: service, maxPerDomain: 2);
      await pool.acquire('s1', domainHint: 'a.dev'); // pool-1
      await pool.acquire('s2', domainHint: 'a.dev'); // pool-2 (no idle yet)
      expect(pool.liveCount, 2);
      await pool.release('s1'); // pool-1 is now the domain's idle

      await pool.acquire('s3', domainHint: 'shop.a.dev');
      expect(port.disposes, 1);
      expect(port.disposed, ['pool-1']); // evicted, not handed over
      expect(port.creates, 3); // FR-6: a fresh instance for the new session
      expect(pool.liveCount, 2);
      expect(pool.sessions(), {'s2', 's3'});
    });

    test('P5d: a domain at cap with every instance active -> pool_exhausted',
        () async {
      final pool = WebviewPool(service: service, maxPerDomain: 1);
      await pool.acquire('s1', domainHint: 'a.dev');
      await expectLater(
        pool.acquire('s2', domainHint: 'shop.a.dev'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'pool_exhausted')),
      );
      expect(port.creates, 1);
      expect(pool.sessions(), {'s1'});
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

    test('P7b: a failed dispose keeps the instance registered', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'a.dev');
      port.failDispose = true;
      await expectLater(pool.disposeAll(), throwsA(isA<WebviewException>()));
      expect(port.disposeAttempts, 1);
      expect(pool.liveCount, 1); // the registry still mirrors reality
      expect(pool.sessions(), {'s1'});
      expect(service.created, {'pool-1'}); // the webview is genuinely alive
    });

    test('P7c: disposeAll attempts every instance, then reports', () async {
      final pool = WebviewPool(service: service);
      await pool.acquire('s1', domainHint: 'a.dev');
      await pool.acquire('s2', domainHint: 'b.dev');
      port.failDispose = true;
      await expectLater(
        pool.disposeAll(),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'pool_teardown_incomplete')),
      );
      expect(port.disposeAttempts, 2); // both attempted, not just the first
      expect(pool.liveCount, 2);

      port.failDispose = false;
      await pool.disposeAll();
      expect(pool.liveCount, 0);
      expect(pool.sessions(), isEmpty);
      expect(service.created, isEmpty);
      expect(port.disposed, ['pool-1', 'pool-2']);
    });
  });
}
