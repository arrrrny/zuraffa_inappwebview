import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

WebviewCaptureEntry _entry({
  String url = 'https://x.dev/api',
  String method = 'GET',
  Map<String, String> requestHeaders = const {},
  String? requestBody,
  int? status = 200,
  String? responseBody = '{"ok":true}',
}) =>
    WebviewCaptureEntry.fromChannelArgs({
      'url': url,
      'method': method,
      'requestHeaders': requestHeaders,
      if (requestBody != null) 'requestBody': requestBody,
      'status': status,
      'responseHeaders': const <String, String>{},
      if (responseBody != null) 'responseBody': responseBody,
    });

void main() {
  group('US1 — codec + filter', () {
    test('C1: decodes the full channel shape', () {
      final e = _entry(
        requestHeaders: {'accept': 'application/json'},
        requestBody: 'a=1',
        responseBody: '[1,2]',
      );
      expect(e.url, 'https://x.dev/api');
      expect(e.method, 'GET');
      expect(e.requestHeaders['accept'], 'application/json');
      expect(e.requestBody, 'a=1');
      expect(e.status, 200);
      expect(e.responseBody, '[1,2]');
      expect(e.at, isNotNull);
    });

    test('C1: filter serializes urlPattern + maxBodyBytes', () {
      expect(
        const WebviewCaptureFilter(
          urlPattern: '/api/',
          maxBodyBytes: 512,
        ).toChannelArgs(),
        {'urlPattern': '/api/', 'maxBodyBytes': 512},
      );
    });

    test('C6: filter.matches is a case-insensitive substring test', () {
      const filter = WebviewCaptureFilter(urlPattern: '/API/');
      expect(filter.matches(_entry(url: 'https://x.dev/api/v2')), isTrue);
      expect(filter.matches(_entry(url: 'https://x.dev/img')), isFalse);
    });
  });

  group('US1 — service guards', () {
    late _CaptureFakePort port;
    late WebviewService service;

    setUp(() async {
      port = _CaptureFakePort();
      service = WebviewService(port: port);
      await service.createHeadless(id: 'w');
    });

    test('C2: setCaptureEnabled reaches the port; guards throw', () async {
      await service.setCaptureEnabled(
        id: 'w',
        enabled: true,
        filter: const WebviewCaptureFilter(urlPattern: '/api/'),
      );
      expect(port.lastCaptureId, 'w');
      expect(port.lastCaptureEnabled, isTrue);
      expect(port.lastCaptureFilter?.urlPattern, '/api/');
      expect(
        () => service.setCaptureEnabled(id: 'nope', enabled: true),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'not_created')),
      );
    });

    test('C2: captureEvents guards + unwired', () {
      expect(
        () => service.captureEvents(id: 'nope'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'not_created')),
      );
      expect(
        () => const UnwiredWebviewPort().captureEvents(id: 'w'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'port_not_wired')),
      );
      expect(
        () => const UnwiredWebviewPort()
            .setCaptureEnabled(id: 'w', enabled: true),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'port_not_wired')),
      );
    });
  });

  group('US2/US3 — manager', () {
    test('C3: ordered buffer + clear + attach/detach', () async {
      final controller = StreamController<WebviewCaptureEntry>();
      final manager = NetworkCaptureManager();
      manager.attach('w', controller.stream);
      controller.add(_entry(url: 'https://x.dev/1'));
      controller.add(_entry(url: 'https://x.dev/2'));
      await Future<void>.delayed(Duration.zero);
      expect(
        manager.entries('w').map((e) => e.url),
        ['https://x.dev/1', 'https://x.dev/2'],
      );
      manager.detach('w');
      controller.add(_entry(url: 'https://x.dev/3'));
      await Future<void>.delayed(Duration.zero);
      expect(manager.entries('w'), hasLength(2));
      manager.clear('w');
      expect(manager.entries('w'), isEmpty);
      await controller.close();
    });

    test('C4: auth-shaped headers + url params redacted at ingest', () {
      final manager = NetworkCaptureManager();
      manager.ingest(
        'w',
        _entry(
          url: 'https://x.dev/p?token=abc&keep=1',
          requestHeaders: {
            'Authorization': 'Bearer xyz',
            'Cookie': 'a=b',
            'Accept': 'json',
          },
        ),
      );
      final e = manager.entries('w').single;
      expect(e.requestHeaders['Authorization'], '<redacted>');
      expect(e.requestHeaders['Cookie'], '<redacted>');
      expect(e.requestHeaders['Accept'], 'json');
      expect(e.url, contains('token=<redacted>'));
      expect(e.url, contains('keep=1'));
    });

    test('C4: redaction off keeps values verbatim', () {
      final manager = NetworkCaptureManager(redactAuth: false);
      manager.ingest(
        'w',
        _entry(
          url: 'https://x.dev/p?token=abc',
          requestHeaders: {'Authorization': 'Bearer xyz'},
        ),
      );
      final e = manager.entries('w').single;
      expect(e.requestHeaders['Authorization'], 'Bearer xyz');
      expect(e.url, contains('token=abc'));
    });

    test('C5: budgets — maxEntries keeps latest, maxBodyBytes truncates',
        () {
      final manager = NetworkCaptureManager(
        budget: const CaptureBudget(maxEntries: 2, maxBodyBytes: 10),
      );
      manager.ingest('w', _entry(url: 'https://x.dev/1'));
      manager.ingest('w', _entry(url: 'https://x.dev/2'));
      manager.ingest(
        'w',
        _entry(url: 'https://x.dev/3', responseBody: 'x' * 100),
      );
      expect(
        manager.entries('w').map((e) => e.url),
        ['https://x.dev/2', 'https://x.dev/3'],
      );
      expect(manager.entries('w').last.responseBody, hasLength(10));
    });
  });

  group('review-fix hardening', () {
    test('C8: malformed percent-encoding in a query key never throws', () {
      final manager = NetworkCaptureManager();
      // Urls are page-controlled: a bad (`a%FF`) or truncated (`b%`)
      // sequence must not throw out of ingest.
      manager.ingest(
        'w',
        _entry(url: 'https://x.dev/p?token=abc&a%FF=1&b%=2&keep=1'),
      );
      final e = manager.entries('w').single;
      expect(e.url, contains('token=<redacted>'));
      expect(e.url, contains('keep=1'));
      expect(e.url, contains('a%FF=1'));
      expect(e.url, contains('b%=2'));
    });

    test('C9: attach contains stream errors instead of crashing the zone',
        () async {
      final controller = StreamController<WebviewCaptureEntry>();
      final manager = NetworkCaptureManager();
      manager.attach('w', controller.stream);
      controller.addError(
        const WebviewException(
          'malformed_response',
          'bad native payload',
          recoverable: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(_entry(url: 'https://x.dev/after-error'));
      await Future<void>.delayed(Duration.zero);
      expect(manager.entries('w').single.url, 'https://x.dev/after-error');
      await controller.close();
    });

    test('C10: maxBodyBytes cuts on a UTF-8 boundary', () {
      final manager = NetworkCaptureManager(
        budget: const CaptureBudget(maxBodyBytes: 4),
      );
      manager.ingest(
        'w',
        _entry(requestBody: 'ééé', responseBody: 'a😀b'),
      );
      final e = manager.entries('w').single;
      // 'a😀b' is 6 bytes; 4 bytes fits only 'a' — the old char-based cut
      // kept the whole 3-character body.
      expect(e.responseBody, 'a');
      expect(e.requestBody, 'éé');
      expect(e.responseBody, isNot(contains('\uFFFD')));
      expect(e.requestBody, isNot(contains('\uFFFD')));
    });

    test('C11: widened secret carriers are redacted too', () {
      final manager = NetworkCaptureManager();
      manager.ingest(
        'w',
        _entry(
          url: 'https://x.dev/p?session_id=abc&signature=sig&keep=1',
          requestHeaders: {'X-Api-Key': 'k', 'X-Amz-Security-Token': 't'},
        ),
      );
      final e = manager.entries('w').single;
      expect(e.requestHeaders['X-Api-Key'], '<redacted>');
      expect(e.requestHeaders['X-Amz-Security-Token'], '<redacted>');
      expect(e.url, contains('session_id=<redacted>'));
      expect(e.url, contains('signature=<redacted>'));
      expect(e.url, contains('keep=1'));
    });
  });
}

class _CaptureFakePort implements WebviewPort {
  String? lastCaptureId;
  bool? lastCaptureEnabled;
  WebviewCaptureFilter? lastCaptureFilter;

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
      const Stream.empty();

  @override
  Future<void> setCaptureEnabled({
    required String id,
    required bool enabled,
    WebviewCaptureFilter? filter,
  }) async {
    lastCaptureId = id;
    lastCaptureEnabled = enabled;
    lastCaptureFilter = filter;
  }

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
