import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

WebviewNavigationEvent _completed(String url) =>
    WebviewNavigationEvent.fromChannelArgs(
        {'type': 'completed', 'url': url});

WebviewCaptureEntry _capture(String url) =>
    WebviewCaptureEntry.fromChannelArgs(
        {'url': url, 'method': 'GET', 'status': 200});

void main() {
  group('US1 — recorder', () {
    test('V1: navigations -> ordered entries with html + cookie snapshots',
        () async {
      final port = _VcrFakePort();
      port.htmlFor = ({required String id}) async => '<html>a</html>';
      port.cookiesFor = ({required String url}) async =>
          [const WebviewCookie(name: 'sid', value: '1')];
      final service = WebviewService(port: port);
      await service.createHeadless(id: 'w');

      final nav = StreamController<WebviewNavigationEvent>();
      final cap = StreamController<WebviewCaptureEntry>();
      final recorder = VcrRecorder(service: service, webviewId: 'w')
        ..record(navigationEvents: nav.stream, captureEvents: cap.stream);

      cap.add(_capture('https://x.dev/api'));
      nav.add(_completed('https://x.dev/a'));
      await Future<void>.delayed(Duration.zero);
      nav.add(_completed('https://x.dev/b'));
      await Future<void>.delayed(Duration.zero);

      final cassette = await recorder.stop();
      expect(cassette.formatVersion, 1);
      expect(cassette.entries, hasLength(2));
      expect(cassette.entries.first.url, 'https://x.dev/a');
      expect(cassette.entries.first.html, '<html>a</html>');
      expect(
        cassette.entries.first.cookies.single.name,
        'sid',
      );
      // captures observed before a navigation attach to that navigation
      expect(cassette.entries.first.captures, hasLength(1));
      expect(cassette.entries.last.captures, isEmpty);

      await nav.close();
      await cap.close();
    });

    test('V2: cassette JSON round-trip preserves entries', () {
      final cassette = Cassette(entries: [
        CassetteEntry(
          url: 'https://x.dev/a',
          html: '<html/>',
          cookies: const [WebviewCookie(name: 'sid', value: '1')],
          captures: [_capture('https://x.dev/api')],
        ),
      ]);
      final back = Cassette.fromJson(cassette.toJson());
      expect(back.formatVersion, 1);
      expect(back.entries.single.url, 'https://x.dev/a');
      expect(back.entries.single.html, '<html/>');
      expect(back.entries.single.cookies.single.name, 'sid');
      expect(back.entries.single.captures.single.url, 'https://x.dev/api');
    });

    test('V2: recorded captures are defensively redacted', () async {
      final port = _VcrFakePort()
        ..htmlFor = ({required String id}) async => '';
      final service = WebviewService(port: port);
      await service.createHeadless(id: 'w');
      final recorder = VcrRecorder(service: service, webviewId: 'w');
      recorder.ingestCapture(
        WebviewCaptureEntry.fromChannelArgs({
          'url': 'https://x.dev/api?token=abc',
          'method': 'GET',
          'requestHeaders': {'Authorization': 'Bearer x'},
        }),
      );
      await recorder.ingestNavigation(_completed('https://x.dev/a'));
      final cassette = await recorder.stop();
      final e = cassette.entries.single;
      expect(e.captures.single.url, contains('token=<redacted>'));
      expect(
        e.captures.single.requestHeaders['Authorization'],
        '<redacted>',
      );
    });
  });

  group('US2/US3 — replayer', () {
    late _VcrFakePort port;
    late WebviewService service;
    late Cassette cassette;

    setUp(() async {
      port = _VcrFakePort();
      service = WebviewService(port: port);
      await service.createHeadless(id: 'w');
      cassette = const Cassette(entries: [
        CassetteEntry(
          url: 'https://x.dev/a',
          html: '<html>A</html>',
          captures: [],
        ),
        CassetteEntry(
          url: 'https://x.dev/a/page/2',
          html: '<html>A2</html>',
          captures: [],
        ),
      ]);
    });

    test('V3: exact match serves recorded html via loadHtml', () async {
      final replayer = VcrReplayer(
        cassette: cassette,
        service: service,
        webviewId: 'w',
      );
      await replayer.loadUrl('https://x.dev/a');
      expect(port.lastHtml, '<html>A</html>');
      expect(port.lastBaseUrl, 'https://x.dev/a');
    });

    test('V4: path-prefix best-match fallback serves nearest entry',
        () async {
      final replayer = VcrReplayer(
        cassette: cassette,
        service: service,
        webviewId: 'w',
      );
      await replayer.loadUrl('https://x.dev/a/page/2?x=1');
      expect(port.lastHtml, '<html>A2</html>');
    });

    test('V5: strict unmatched -> typed vcr_unmatched naming the url',
        () async {
      final replayer = VcrReplayer(
        cassette: cassette,
        service: service,
        webviewId: 'w',
      );
      await expectLater(
        replayer.loadUrl('https://other.dev/'),
        throwsA(isA<WebviewException>().having(
          (e) => e.code,
          'code',
          'vcr_unmatched',
        ).having(
          (e) => e.message,
          'message',
          contains('https://other.dev/'),
        )),
      );
    });

    test('V5: soft unmatched completes without serving', () async {
      final replayer = VcrReplayer(
        cassette: cassette,
        service: service,
        webviewId: 'w',
        strict: false,
      );
      await replayer.loadUrl('https://other.dev/');
      expect(port.lastHtml, isNull);
    });

    test('V6: served entry synthesizes its captures on the stream',
        () async {
      final withCaptures = Cassette(entries: [
        CassetteEntry(
          url: 'https://x.dev/a',
          html: '<html>A</html>',
          captures: [_capture('https://x.dev/api/1'), _capture('https://x.dev/api/2')],
        ),
      ]);
      final replayer = VcrReplayer(
        cassette: withCaptures,
        service: service,
        webviewId: 'w',
      );
      final seen = <WebviewCaptureEntry>[];
      final sub = replayer.captureEvents.listen(seen.add);
      await replayer.loadUrl('https://x.dev/a');
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((e) => e.url), [
        'https://x.dev/api/1',
        'https://x.dev/api/2',
      ]);
      await sub.cancel();
    });
  });
}

class _VcrFakePort implements WebviewPort {
  String? lastHtml;
  String? lastBaseUrl;
  String? _loadedUrl;
  Future<String?> Function({required String id})? htmlFor;
  Future<List<WebviewCookie>> Function({required String url})? cookiesFor;

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
  }) async =>
      _loadedUrl = url.toString();

  @override
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) async {
    lastHtml = html;
    lastBaseUrl = baseUrl;
  }

  @override
  Future<String?> currentUrl({required String id}) async => _loadedUrl;

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async =>
      null;

  @override
  Future<String?> getHtml({required String id}) =>
      htmlFor?.call(id: id) ?? Future.value(null);

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) =>
      cookiesFor?.call(url: url) ?? Future.value(const []);

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
