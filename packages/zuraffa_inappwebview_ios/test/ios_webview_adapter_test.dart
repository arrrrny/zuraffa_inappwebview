import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';
import 'package:zuraffa_inappwebview_ios/zuraffa_inappwebview_ios.dart';

void main() {
  late Map<String, Object?> lastArgs;
  late String? lastMethod;
  late IosWebviewPort port;

  IosWebviewChannel scripted({
    Object? payload,
    Object? nativeError,
  }) =>
      IosWebviewChannel(
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

  group('IosWebviewPort over the envelope (WA1-WA6)', () {
    test('WA1: isSupported decodes the supported flag', () async {
      port = IosWebviewPort(channel: scripted(payload: {'supported': true}));
      expect(await port.isSupported(), isTrue);
      expect(lastMethod, 'isSupported');
    });

    test('WA2: createHeadless ships id + settings args', () async {
      port = IosWebviewPort(channel: scripted(payload: {'ok': true}));
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
      port = IosWebviewPort(channel: scripted(payload: {'ok': true}));
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
      port = IosWebviewPort(channel: scripted(payload: {'result': 42}));
      final out = await port.evaluateJavascript(id: 'w', source: '1+1');
      expect(out, 42);
    });

    test('WA5: getCookies decodes the cookie list', () async {
      port = IosWebviewPort(channel: scripted(payload: {
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
      port = IosWebviewPort(channel: scripted(nativeError: {
        'code': 'webview_dead',
        'message': 'renderer crashed',
      }));
      await expectLater(
        port.createHeadless(id: 'w'),
        throwsA(isA<IosWebviewException>()
            .having((e) => e.code, 'code', 'webview_dead')
            .having((e) => e.recoverable, 'recoverable', isFalse)),
      );
    });
  });

  group('capture ops (spec 003)', () {
    test('S6: takeScreenshot forwards config args and decodes data',
        () async {
      port = IosWebviewPort(channel: scripted(payload: {
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

    test('S6: null data passes through as null', () async {
      port = IosWebviewPort(channel: scripted(payload: {'data': null}));
      expect(await port.takeScreenshot(id: 'w'), isNull);
    });

    test('S6: non-list data raises malformed_response', () async {
      port = IosWebviewPort(channel: scripted(payload: {'data': 'oops'}));
      await expectLater(
        port.takeScreenshot(id: 'w'),
        throwsA(isA<IosWebviewException>()
            .having((e) => e.code, 'code', 'malformed_response')),
      );
    });

    test('S6: exportPdf rides its own method name', () async {
      port = IosWebviewPort(channel: scripted(payload: {
        'data': [9, 8, 7],
      }));
      expect(await port.exportPdf(id: 'w'), [9, 8, 7]);
      expect(lastMethod, 'exportPdf');
      expect(lastArgs['id'], 'w');
    });
  });
}
