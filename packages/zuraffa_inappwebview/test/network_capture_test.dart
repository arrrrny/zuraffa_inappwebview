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

    test('C1: drifted field types decode without throwing', () {
      final e = WebviewCaptureEntry.fromChannelArgs(const {
        'url': 'https://x.dev/api',
        'method': 'GET',
        'requestHeaders': {'x-attempt': 2},
        'status': '200',
        'responseHeaders': 'not-a-map',
      });
      expect(e.status, 200);
      expect(e.requestHeaders['x-attempt'], '2');
      expect(e.responseHeaders, isEmpty);
      expect(
        WebviewCaptureEntry.fromChannelArgs(const {'status': 200.5}).status,
        200,
      );
      expect(
        WebviewCaptureEntry.fromChannelArgs(const {'status': 'nope'}).status,
        isNull,
      );
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

    test('C7: the default service stream is redacted (SC-3)', () async {
      final controller = StreamController<WebviewCaptureEntry>();
      port.captureStream = controller.stream;
      final seen = <WebviewCaptureEntry>[];
      final sub = service.captureEvents(id: 'w').listen(seen.add);
      controller.add(_entry(
        url: 'https://x.dev/p?token=abc&keep=1',
        requestHeaders: {'Authorization': 'Bearer xyz', 'Accept': 'json'},
      ));
      await Future<void>.delayed(Duration.zero);
      final e = seen.single;
      expect(e.requestHeaders['Authorization'], '<redacted>');
      expect(e.requestHeaders['Accept'], 'json');
      expect(e.url, contains('token=<redacted>'));
      expect(e.url, contains('keep=1'));
      await sub.cancel();
      await controller.close();
    });

    test('C7: redact: false is the explicit trusted-consumer opt-out',
        () async {
      final controller = StreamController<WebviewCaptureEntry>();
      port.captureStream = controller.stream;
      final seen = <WebviewCaptureEntry>[];
      final sub =
          service.captureEvents(id: 'w', redact: false).listen(seen.add);
      controller.add(_entry(
        url: 'https://x.dev/p?token=abc',
        requestHeaders: {'Authorization': 'Bearer xyz'},
      ));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single.requestHeaders['Authorization'], 'Bearer xyz');
      expect(seen.single.url, contains('token=abc'));
      await sub.cancel();
      await controller.close();
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

    test('C4: the fragment is redacted independently of the query', () {
      const redactor = CaptureSecretRedactor();
      expect(
        redactor.redactUrl('https://x.dev/p?keep=1#token=abc'),
        'https://x.dev/p?keep=1#token=<redacted>',
      );
      expect(
        redactor.redactUrl('https://x.dev/p?token=abc#token=def'),
        'https://x.dev/p?token=<redacted>#token=<redacted>',
      );
      expect(
        redactor.redactUrl('https://x.dev/p#section-2'),
        'https://x.dev/p#section-2',
      );
      expect(redactor.redactUrl('https://x.dev/p'), 'https://x.dev/p');
    });

    test('C5: maxBodyBytes is a UTF-8 byte cap that never splits a character',
        () {
      final manager = NetworkCaptureManager(
        budget: const CaptureBudget(maxBodyBytes: 10),
      );
      manager.ingest('w', _entry(responseBody: 'é' * 100));
      final cropped = manager.entries('w').last.responseBody!;
      expect(cropped, 'é' * 5); // 10 UTF-8 bytes — 10 code units would be 20
      expect(cropped.codeUnits, hasLength(5));

      final tight = NetworkCaptureManager(
        budget: const CaptureBudget(maxBodyBytes: 1),
      );
      tight.ingest('w', _entry(responseBody: '🎉'));
      // 4 bytes do not fit in 1: drop the body rather than hand a consumer a
      // lone surrogate that no longer round-trips through UTF-8.
      expect(tight.entries('w').last.responseBody, '');
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
}

class _CaptureFakePort implements WebviewPort {
  String? lastCaptureId;
  bool? lastCaptureEnabled;
  WebviewCaptureFilter? lastCaptureFilter;

  /// The stream [captureEvents] hands back (spec 005 US1).
  Stream<WebviewCaptureEntry> captureStream = const Stream.empty();

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
      captureStream;

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
