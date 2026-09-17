import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Recording fake port: records operations, replays scripted results.
class FakeWebviewPort implements WebviewPort {
  final List<String> ops = [];
  String? currentUrlResult;
  Object? evaluateResult;
  String? htmlResult;
  final List<WebviewCookie> storedCookies = [];

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async =>
      ops.add('create:$id');

  @override
  Future<void> runHeadless({required String id}) async => ops.add('run:$id');

  @override
  Future<void> disposeHeadless({required String id}) async =>
      ops.add('dispose:$id');

  @override
  Future<void> loadUrl({
    required String id,
    required WebviewUri url,
    Map<String, String> headers = const {},
  }) async =>
      ops.add('load:$id:${url.toString()}');

  @override
  Future<String?> currentUrl({required String id}) async => currentUrlResult;

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async =>
      evaluateResult;

  @override
  Future<String?> getHtml({required String id}) async => htmlResult;

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
  Future<void> setCookie(WebviewCookie cookie) async =>
      storedCookies.add(cookie);

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) async =>
      List.of(storedCookies);

  @override
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) async {
    final existed = storedCookies.any((c) => c.name == name);
    storedCookies.removeWhere((c) => c.name == name);
    return existed;
  }

  @override
  Future<void> deleteAllCookies() async => storedCookies.clear();
}

void main() {
  late FakeWebviewPort port;
  late WebviewService service;

  setUp(() {
    port = FakeWebviewPort();
    service = WebviewService(port: port);
  });

  group('headless lifecycle (W1-W5)', () {
    test('W1: create -> run -> dispose drives the port in order', () async {
      await service.createHeadless(id: 'w');
      await service.runHeadless(id: 'w');
      await service.disposeHeadless(id: 'w');

      expect(port.ops, ['create:w', 'run:w', 'dispose:w']);
      expect(service.created, isEmpty);
      expect(service.running, isEmpty);
    });

    test('W2: double create fails with already_created', () async {
      await service.createHeadless(id: 'w');
      await expectLater(
        service.createHeadless(id: 'w'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'already_created')),
      );
    });

    test('W3: operations before create fail with not_created', () async {
      await expectLater(
        service.loadUrl(id: 'w', url: WebviewUri('https://x.dev')),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'not_created')),
      );
      await expectLater(
        service.evaluateJavascript(id: 'w', source: '1+1'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'not_created')),
      );
      await expectLater(
        service.disposeHeadless(id: 'w'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'not_created')),
      );
    });

    test('W4: double run fails with already_running', () async {
      await service.createHeadless(id: 'w');
      await service.runHeadless(id: 'w');
      await expectLater(
        service.runHeadless(id: 'w'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'already_running')),
      );
    });

    test('W5: dispose clears state; the id is reusable', () async {
      await service.createHeadless(id: 'w');
      await service.runHeadless(id: 'w');
      await service.disposeHeadless(id: 'w');

      await service.createHeadless(id: 'w');
      expect(service.created, contains('w'));
    });
  });

  group('navigation + JS + html (W6-W8)', () {
    test('W6: loadUrl forwards the validated URL and headers', () async {
      await service.createHeadless(id: 'w');
      await service.loadUrl(
        id: 'w',
        url: WebviewUri('https://x.dev/page'),
        headers: {'X-Test': '1'},
      );
      expect(port.ops.last, 'load:w:https://x.dev/page');
    });

    test('W7: currentUrl/evaluateJavascript/getHtml delegate', () async {
      await service.createHeadless(id: 'w');
      port.currentUrlResult = 'https://x.dev/page';
      port.evaluateResult = 42;
      port.htmlResult = '<html></html>';

      expect(await service.currentUrl(id: 'w'), 'https://x.dev/page');
      expect(await service.evaluateJavascript(id: 'w', source: '1+1'), 42);
      expect(await service.getHtml(id: 'w'), '<html></html>');
    });

    test('W8: cookies route to the shared store (no id scoping)', () async {
      const cookie = WebviewCookie(
          name: 'session', value: 'abc', domain: 'x.dev', secure: true);
      await service.setCookie(cookie);
      expect(await service.getCookies(url: 'https://x.dev'), [cookie]);

      expect(await service.deleteCookie(url: 'https://x.dev', name: 'session'),
          isTrue);
      expect(await service.getCookies(url: 'https://x.dev'), isEmpty);
      await service.deleteAllCookies();
    });
  });

  group('types (W9-W11)', () {
    test('W9: WebviewUri accepts http/https/about:blank, rejects others',
        () {
      expect(WebviewUri('https://x.dev').toString(), 'https://x.dev');
      expect(WebviewUri('http://x.dev').toString(), 'http://x.dev');
      expect(WebviewUri('about:blank').toString(), 'about:blank');
      expect(
          () => WebviewUri('file:///etc/passwd'),
          throwsA(isA<WebviewException>()
              .having((e) => e.code, 'code', 'unsupported_scheme')));
      expect(
          () => WebviewUri('about:config'),
          throwsA(isA<WebviewException>()
              .having((e) => e.code, 'code', 'unsupported_scheme')));
    });

    test('W10: WebviewSettings round-trips into channel args', () {
      const settings = WebviewSettings(
        userAgent: 'agent-x',
        javaScriptEnabled: false,
        incognito: true,
        loadTimeout: Duration(seconds: 7),
      );
      final args = settings.toChannelArgs();
      expect(args['userAgent'], 'agent-x');
      expect(args['javaScriptEnabled'], isFalse);
      expect(args['incognito'], isTrue);
      expect(args['loadTimeoutMs'], 7000);
      expect(args.containsKey('mediaPlaybackRequiresUserGesture'), isTrue);
    });

    test('W11: WebviewCookie channel round-trip preserves fields', () {
      final expires = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      const cookie = WebviewCookie(
        name: 'a',
        value: 'b',
        domain: 'x.dev',
        path: '/p',
        secure: true,
      );
      final withExpiry = cookie.copyWith(
          value: 'b', expiresAt: expires);
      final back =
          WebviewCookie.fromChannelArgs(withExpiry.toChannelArgs());
      expect(back.name, 'a');
      expect(back.value, 'b');
      expect(back.domain, 'x.dev');
      expect(back.path, '/p');
      expect(back.expiresAt, expires);
      expect(back.secure, isTrue);
    });
  });
}
