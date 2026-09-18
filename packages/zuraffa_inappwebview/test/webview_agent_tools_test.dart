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
    test('A1: six tools, named, described, object schemas; idempotent',
        () {
      expect(tools.map((t) => t.name), [
        'browse',
        'execute_js',
        'read_cookies',
        'screenshot',
        'dismiss_dialogues',
        'release_session',
      ]);
      for (final t in tools) {
        expect(t.description, isNotEmpty);
        expect(t.inputSchema['type'], 'object');
      }
      final again =
          WebviewAgentTools(service: service, pool: pool).buildTools();
      expect(again.map((t) => t.name), tools.map((t) => t.name));
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
    });

    test('A3: execute_js reuses the same pooled webview for the session',
        () async {
      final first = await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      final second = await tool('execute_js')
          .call({'session': 's1', 'source': 'document.title'});
      expect(second.isError, isFalse);
      expect(second.data?['webviewId'], first.data?['webviewId']);
      expect(port.evaluatedSources, contains('document.title'));
      expect(port.creates, 1);
    });

    test('A4: typed failure degrades to isError result (no throw)',
        () async {
      final result = await tool('browse')
          .call({'session': 's1', 'url': 'ftp://x.dev/a'});
      expect(result.isError, isTrue);
      expect(result.text, contains('unsupported_scheme'));
    });

    test('A4: missing argument -> isError with a clear message', () async {
      final result = await tool('browse').call({'session': 's1'});
      expect(result.isError, isTrue);
      expect(result.text, contains('url'));
    });
  });

  group('US3 — read, capture, clean, release', () {
    test('A5: read_cookies returns the cookie list', () async {
      port.cookiesFor = ({required String url}) async =>
          [const WebviewCookie(name: 'sid', value: '1')];
      final result = await tool('read_cookies')
          .call({'url': 'https://x.dev'});
      expect(result.isError, isFalse);
      final cookies = result.data?['cookies'] as List;
      expect(cookies.single['name'], 'sid');
    });

    test('A6: screenshot returns artifactRef + byteLength, no body',
        () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      port.screenshotBytes = [1, 2, 3, 4];
      final result =
          await tool('screenshot').call({'session': 's1'});
      expect(result.isError, isFalse);
      expect(result.data?['byteLength'], 4);
      expect(result.artifactRef, isNotNull);
      expect(result.data?.containsKey('bytes'), isFalse);
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

    test('A8: release_session returns the instance to the pool',
        () async {
      await tool('browse')
          .call({'session': 's1', 'url': 'https://x.dev/a'});
      final result =
          await tool('release_session').call({'session': 's1'});
      expect(result.isError, isFalse);
      expect(pool.sessions(), isEmpty);
    });
  });
}

class _ToolsFakePort implements WebviewPort {
  int creates = 0;
  final List<String> loadedUrls = [];
  final List<String> evaluatedSources = [];
  List<int>? screenshotBytes;
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
    return null;
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
  }) async =>
      screenshotBytes;

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
