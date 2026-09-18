import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';
import 'package:zuraffa_inappwebview_android/zuraffa_inappwebview_android.dart';

void main() {
  late Map<String, Object?> lastArgs;
  late String? lastMethod;
  late AndroidWebviewPort port;

  AndroidWebviewChannel scripted({
    Object? payload,
    Object? nativeError,
  }) =>
      AndroidWebviewChannel(
        invoke: (method, args) async {
          lastMethod = method;
          lastArgs = args;
          if (nativeError != null) return {'error': nativeError};
          return payload;
        },
      );

  setUp(() {
    lastMethod = null;
    lastArgs = const {};
  });

  group('AndroidWebviewPort over the envelope (WA1-WA6)', () {
    test('WA1: isSupported decodes the supported flag', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'supported': true}));
      expect(await port.isSupported(), isTrue);
      expect(lastMethod, 'isSupported');
    });

    test('WA2: createHeadless ships id + settings args', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'ok': true}));
      await port.createHeadless(
        id: 'w',
        settings: const WebviewSettings(userAgent: 'ua', incognito: true),
      );
      expect(lastMethod, 'createHeadless');
      expect(lastArgs['id'], 'w');
      expect(lastArgs['userAgent'], 'ua');
      expect(lastArgs['incognito'], isTrue);
    });

    test('WA3: loadUrl ships the url string and headers', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'ok': true}));
      await port.loadUrl(
        id: 'w',
        url: WebviewUri('https://x.dev/'),
        headers: {'X-A': 'b'},
      );
      expect(lastMethod, 'loadUrl');
      expect(lastArgs['url'], 'https://x.dev/');
      expect((lastArgs['headers'] as Map)['X-A'], 'b');
    });

    test('WA4: evaluateJavascript returns the native result', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'result': 42}));
      final out = await port.evaluateJavascript(id: 'w', source: '1+1');
      expect(out, 42);
    });

    test('WA5: getCookies decodes the cookie list', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {
        'cookies': [
          {'name': 'a', 'value': 'b', 'domain': 'x.dev', 'path': '/', 'secure': true},
        ],
      }));
      final cookies = await port.getCookies(url: 'https://x.dev');
      expect(cookies.single.name, 'a');
      expect(cookies.single.domain, 'x.dev');
      expect(cookies.single.secure, isTrue);
    });

    test('WA6: native errors surface as the adapter typed failure',
        () async {
      port = AndroidWebviewPort(channel: scripted(nativeError: {
        'code': 'webview_dead',
        'message': 'renderer crashed',
      }));
      await expectLater(
        port.createHeadless(id: 'w'),
        throwsA(isA<AndroidWebviewException>()
            .having((e) => e.code, 'code', 'webview_dead')
            .having((e) => e.recoverable, 'recoverable', isFalse)),
      );
    });
  });

  group('capture ops (spec 003)', () {
    test('S6a: takeScreenshot forwards config args and decodes data',
        () async {
      port = AndroidWebviewPort(channel: scripted(payload: {
        'data': [1, 2, 3],
      }));
      final bytes = await port.takeScreenshot(
        id: 'w',
        config: const ScreenshotConfiguration(
          format: ScreenshotFormat.jpeg,
          quality: 80,
        ),
      );
      expect(bytes, [1, 2, 3]);
      expect(lastMethod, 'takeScreenshot');
      expect(lastArgs['id'], 'w');
      expect(lastArgs['format'], 'jpeg');
      expect(lastArgs['quality'], 80);
    });

    test('S6a: null data passes through as null', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'data': null}));
      expect(await port.takeScreenshot(id: 'w'), isNull);
    });

    test('S6a: non-list data raises malformed_response', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'data': 'oops'}));
      await expectLater(
        port.takeScreenshot(id: 'w'),
        throwsA(isA<AndroidWebviewException>()
            .having((e) => e.code, 'code', 'malformed_response')),
      );
    });

    test('S6a: exportPdf rides its own method name', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {
        'data': [9, 8, 7],
      }));
      expect(await port.exportPdf(id: 'w'), [9, 8, 7]);
      expect(lastMethod, 'exportPdf');
      expect(lastArgs['id'], 'w');
    });
  });
}
