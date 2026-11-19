import 'dart:async';

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

    test('S6a: non-integer data element raises malformed_response', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {
        'data': [1, 1.5],
      }));
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

  group('navigation events (spec 004)', () {
    late StreamController<Object?> events;

    AndroidWebviewChannel wired() => AndroidWebviewChannel(
          invoke: (m, a) async => {'ok': true},
          eventSource: (method) => method == 'navigationEvents'
              ? events.stream.asBroadcastStream()
              : const Stream.empty(),
        );

    setUp(() => events = StreamController<Object?>());
    tearDown(() => unawaited(events.close()));

    test('N7: decodes and filters by id', () async {
      port = AndroidWebviewPort(channel: wired());
      final seen = <WebviewNavigationEvent>[];
      final sub = port.navigationEvents(id: 'w').listen(seen.add);
      events.add({'id': 'other', 'type': 'started', 'url': 'x'});
      events.add({'id': 'w', 'type': 'started', 'url': 'https://x.dev/'});
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      expect(seen.single.url, 'https://x.dev/');
      expect(seen.single.phase, WebviewNavigationPhase.started);
      await sub.cancel();
    });

    test('N7: non-map payload -> malformed_response stream error', () async {
      port = AndroidWebviewPort(channel: wired());
      final stream = port.navigationEvents(id: 'w');
      final probe = expectLater(
        stream,
        emitsError(isA<AndroidWebviewException>()
            .having((e) => e.code, 'code', 'malformed_response')),
      );
      await Future<void>.delayed(Duration.zero);
      events.add('oops');
      await probe;
    });

    test('N7: missing event source -> channel_not_wired', () async {
      port = AndroidWebviewPort(
        channel: AndroidWebviewChannel(invoke: (m, a) async => {'ok': true}),
      );
      await expectLater(
        port.navigationEvents(id: 'w'),
        emitsError(isA<AndroidWebviewException>()
            .having((e) => e.code, 'code', 'channel_not_wired')),
      );
    });
  });

  group('network capture (spec 005)', () {
    test('C7: setCaptureEnabled ships id + enabled + filter args',
        () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'ok': true}));
      await port.setCaptureEnabled(
        id: 'w',
        enabled: true,
        filter: const WebviewCaptureFilter(urlPattern: '/api/', maxBodyBytes: 512),
      );
      expect(lastMethod, 'setCaptureEnabled');
      expect(lastArgs['id'], 'w');
      expect(lastArgs['enabled'], isTrue);
      expect(lastArgs['urlPattern'], '/api/');
      expect(lastArgs['maxBodyBytes'], 512);
    });

    test('C7: captureEvents decodes + filters by id', () async {
      final events = StreamController<Object?>();
      addTearDown(() => unawaited(events.close()));
      port = AndroidWebviewPort(channel: AndroidWebviewChannel(
        invoke: (m, a) async => {'ok': true},
        eventSource: (method) => method == 'captureEvents'
            ? events.stream.asBroadcastStream()
            : const Stream.empty(),
      ));
      final seen = <WebviewCaptureEntry>[];
      final sub = port.captureEvents(id: 'w').listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      events.add({'id': 'other', 'url': 'x'});
      events.add({
        'id': 'w',
        'url': 'https://x.dev/api',
        'method': 'POST',
        'status': 201,
      });
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      expect(seen.single.url, 'https://x.dev/api');
      expect(seen.single.method, 'POST');
      expect(seen.single.status, 201);
      await sub.cancel();
    });

    test('C7: non-map capture event -> malformed_response', () async {
      final events = StreamController<Object?>();
      addTearDown(() => unawaited(events.close()));
      port = AndroidWebviewPort(channel: AndroidWebviewChannel(
        invoke: (m, a) async => {'ok': true},
        eventSource: (method) => method == 'captureEvents'
            ? events.stream
            : const Stream.empty(),
      ));
      final bad = expectLater(
        port.captureEvents(id: 'w'),
        emitsError(isA<AndroidWebviewException>()
            .having((e) => e.code, 'code', 'malformed_response')),
      );
      await Future<void>.delayed(Duration.zero);
      events.add('oops');
      await bad;
    });

    test('C7: missing event source -> channel_not_wired', () async {
      port = AndroidWebviewPort(
        channel: AndroidWebviewChannel(invoke: (m, a) async => {'ok': true}),
      );
      await expectLater(
        port.captureEvents(id: 'w'),
        emitsError(isA<AndroidWebviewException>()
            .having((e) => e.code, 'code', 'channel_not_wired')),
      );
    });
  });

  group('loadHtml (spec 008)', () {
    test('V7: ships id + html + baseUrl on the envelope', () async {
      port = AndroidWebviewPort(channel: scripted(payload: {'ok': true}));
      await port.loadHtml(
        id: 'w',
        html: '<html/>',
        baseUrl: 'https://x.dev/a',
      );
      expect(lastMethod, 'loadHtml');
      expect(lastArgs['id'], 'w');
      expect(lastArgs['html'], '<html/>');
      expect(lastArgs['baseUrl'], 'https://x.dev/a');
    });
  });
}
