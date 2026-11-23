import 'dart:convert';

import 'package:test/test.dart';
import 'package:zuraffa/zuraffa.dart' show McpTool;
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

void main() {
  late _ToolsFakePort port;
  late WebviewService service;
  late WebviewPool pool;
  late List<McpTool> tools;

  setUp(() async {
    port = _ToolsFakePort();
    service = WebviewService(port: port);
    pool = WebviewPool(service: service);
    tools = WebviewAgentTools(service: service, pool: pool).buildTools();
  });

  McpTool tool(String name) =>
      tools.firstWhere((t) => t.name == name, orElse: () {
        fail('missing tool $name');
      });

  group('US1 — suite', () {
    test('A1: six tools, named, described, with the documented schemas', () {
      expect(tools.map((t) => t.name), [
        'browse',
        'execute_js',
        'read_cookies',
        'screenshot',
        'dismiss_dialogues',
        'release_session',
      ]);
      // Pinned per tool: a copy-paste drift (a handler reading an argument
      // its schema does not declare) must fail here, not at agent runtime.
      const expected = {
        'browse': ['session', 'url'],
        'execute_js': ['session', 'source'],
        'read_cookies': ['url'],
        'screenshot': ['session'],
        'dismiss_dialogues': ['session'],
        'release_session': ['session'],
      };
      for (final t in tools) {
        expect(t.description, isNotEmpty);
        expect(t.inputSchema['type'], 'object');
        expect(
          (t.inputSchema['properties'] as Map).keys.toList(),
          expected[t.name],
        );
        expect(t.inputSchema['required'], expected[t.name]);
      }
    });
  });

  group('US2 — browse + continuity', () {
    test('A2: browse acquires pooled instance and loads the validated url',
        () async {
      final result = await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      expect(result.isError, isFalse);
      expect(port.loadedUrls, contains('https://x.dev/a'));
      expect(result.data?['webviewId'], isNotNull);
      expect(result.text, contains('webviewId'));
    });

    test('A3: execute_js reuses the same pooled webview and reports the value',
        () async {
      final first = await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      port.evaluateResult = 'the-title';
      final second = await tool('execute_js')
          .call({'session': 's1', 'source': 'document.title'});
      expect(second.isError, isFalse);
      expect(second.data?['webviewId'], first.data?['webviewId']);
      expect(port.evaluatedSources, contains('document.title'));
      expect(port.creates, 1);
      // The payload must ride `text`: `data` is not serialised on the wire.
      expect(second.text, contains('the-title'));
    });

    test('A4: typed failure degrades to isError result (no throw)',
        () async {
      final result = await tool('browse')
          .call({'session': 's1', 'url': 'ftp://x.dev/a'});
      expect(result.isError, isTrue);
      expect(result.text, contains('unsupported_scheme'));
    });

    test('A4: an untyped port failure degrades to tool_failed', () async {
      await tool('browse').call({'session': 's1', 'url': 'https://x.dev/a'});
      port.failEvaluate = StateError('boom');
      final result = await tool('execute_js')
          .call({'session': 's1', 'source': '1+1'});
      expect(result.isError, isTrue);
      expect(result.text, contains('webview.tool_failed'));
    });

    test('A4: missing argument -> isError with a clear message', () async {
      final result = await tool('browse').call({'session': 's1'});
      expect(result.isError, isTrue);
      expect(result.text, contains('url'));
    });
  });

  group('US3 — read, capture, clean, release', () {
    test('A5: read_cookies returns the list in data *and* text', () async {
      port.cookiesFor = ({required String url}) async =>
          [const WebviewCookie(name: 'sid', value: '1')];
      final result = await tool('read_cookies')
          .call({'url': 'https://x.dev'});
      expect(result.isError, isFalse);
      final cookies = result.data?['cookies'] as List;
      expect(cookies.single['name'], 'sid');
      expect(result.text, contains('sid'));
      expect(result.text, contains('1'));
    });

    test('A5: read_cookies validates the url like every other tool',
        () async {
      final result =
          await tool('read_cookies').call({'url': 'file:///etc/passwd'});
      expect(result.isError, isTrue);
      expect(result.text, contains('unsupported_scheme'));
    });

    test('A6: screenshot returns the bytes to the caller without a sink',
        () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      port.screenshotBytes = [1, 2, 3, 4];
      final result =
          await tool('screenshot').call({'session': 's1'});
      expect(result.isError, isFalse);
      expect(result.data?['byteLength'], 4);
      // No sink: no unresolvable ref, and the bytes reach the caller.
      expect(result.artifactRef, isNull);
      expect(result.text, contains(base64Encode([1, 2, 3, 4])));
      expect(result.data?.containsKey('bytes'), isFalse);
      // The format reaches the platform instead of relying on the default.
      expect(port.screenshotConfigs.single?.format, ScreenshotFormat.png);
    });

    test('A6: a host artifact sink keeps the body off the wire', () async {
      final sinkTools = WebviewAgentTools(
        service: service,
        pool: pool,
        artifactSink: (webviewId, bytes) async {
          expect(bytes, [1, 2, 3, 4]);
          return 'file:///tmp/$webviewId.png';
        },
      ).buildTools();
      final screenshot =
          sinkTools.firstWhere((t) => t.name == 'screenshot');
      await tool('browse').call({'session': 's1', 'url': 'https://x.dev/a'});
      port.screenshotBytes = [1, 2, 3, 4];
      final result = await screenshot.call({'session': 's1'});
      expect(result.isError, isFalse);
      expect(result.artifactRef, startsWith('file:///tmp/'));
      expect(result.text, isNot(contains(base64Encode([1, 2, 3, 4]))));
      expect(result.data?['byteLength'], 4);
    });

    test('A6: no bytes -> typed capture_failed', () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      port.screenshotBytes = null;
      final result = await tool('screenshot').call({'session': 's1'});
      expect(result.isError, isTrue);
      expect(result.text, contains('capture_failed'));
    });

    test('A7: dismiss_dialogues applies the canonical script', () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      final result =
          await tool('dismiss_dialogues').call({'session': 's1'});
      expect(result.isError, isFalse);
      expect(port.evaluatedSources,
          contains(contains('getComputedStyle')));
    });

    test('A8: release_session returns the instance to the pool', () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      final result =
          await tool('release_session').call({'session': 's1'});
      expect(result.isError, isFalse);
      expect(pool.sessions(), isEmpty);
    });
  });

  group('US4 — session guard', () {
    for (final name in const [
      'execute_js',
      'screenshot',
      'dismiss_dialogues',
      'release_session',
    ]) {
      test('A9: $name refuses a session that was never started', () async {
        final result = await tool(name).call({
          'session': 'ghost',
          if (name == 'execute_js') 'source': '1+1',
        });
        expect(result.isError, isTrue);
        expect(result.text, contains('session_not_started'));
        expect(port.creates, 0);
      });
    }

    test('A9: a released session is no longer addressable', () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      await tool('release_session').call({'session': 's1'});
      final result =
          await tool('execute_js').call({'session': 's1', 'source': '1+1'});
      expect(result.isError, isTrue);
      expect(result.text, contains('session_not_started'));
    });
  });
}

class _ToolsFakePort implements WebviewPort {
  int creates = 0;
  final List<String> loadedUrls = [];
  final List<String> evaluatedSources = [];
  final List<ScreenshotConfiguration?> screenshotConfigs = [];
  List<int>? screenshotBytes;
  Object? evaluateResult;
  Object? failEvaluate;
  Future<List<WebviewCookie>> Function({required String url})? cookiesFor;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> createHeadless({
    required String id,
    WebviewSettings settings = const WebviewSettings(),
  }) async =>
      creates++;

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
      loadedUrls.add(url.toString());

  @override
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) async {}

  @override
  Future<String?> currentUrl({required String id}) async => null;

  @override
  Future<Object?> evaluateJavascript({
    required String id,
    required String source,
  }) async {
    evaluatedSources.add(source);
    final failure = failEvaluate;
    if (failure != null) throw failure;
    return evaluateResult;
  }

  @override
  Future<String?> getHtml({required String id}) async => null;

  @override
  Future<List<WebviewCookie>> getCookies({required String url}) =>
      cookiesFor?.call(url: url) ?? Future.value(const []);

  @override
  Future<List<int>?> takeScreenshot({
    required String id,
    ScreenshotConfiguration? config,
  }) async {
    screenshotConfigs.add(config);
    return screenshotBytes;
  }

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
