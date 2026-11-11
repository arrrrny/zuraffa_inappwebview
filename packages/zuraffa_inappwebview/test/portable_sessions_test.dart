import 'dart:convert';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

void main() {
  late MemorySessionStore store;
  late _SessionsFakePort port;
  late WebviewService service;
  late WebViewSessions sessions;

  setUp(() async {
    store = MemorySessionStore();
    port = _SessionsFakePort();
    service = WebviewService(port: port);
    await service.createHeadless(id: 'w');
    sessions = WebViewSessions(service: service, store: store);
  });

  group('US1 — save', () {
    test('PS1: snapshots cookies + localStorage into the store', () async {
      port.cookiesFor = ({required String url}) async =>
          [const WebviewCookie(name: 'sid', value: '1')];
      port.evaluateResult = '{"theme":"dark"}';

      await sessions.save(webviewId: 'w', name: 'shop', origin: 'https://x.dev');

      expect(port.evaluatedSources, contains(contains('JSON.stringify')));
      final saved = store.read('shop');
      expect(saved, isNotNull);
      expect(saved!.origin, 'https://x.dev');
      expect(saved.cookies.single.name, 'sid');
      expect(saved.localStorage['theme'], 'dark');
      expect(saved.savedAt, isNotNull);
    });

    test('PS6: a non-JSON localStorage read fails typed, not with '
        'FormatException', () async {
      port.evaluateResult = 'undefined';

      await expectLater(
        sessions.save(webviewId: 'w', name: 'shop', origin: 'https://x.dev'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'local_storage_unreadable')
            .having((e) => e.recoverable, 'recoverable', isTrue)),
      );
      expect(store.read('shop'), isNull);
    });
  });

  group('US2 — load', () {
    test('PS2: re-applies cookies + localStorage writes', () async {
      await store.save(PortableSession(
        name: 'shop',
        origin: 'https://x.dev',
        cookies: const [WebviewCookie(name: 'sid', value: '1')],
        localStorage: const {'theme': 'dark'},
      ));

      await sessions.load(webviewId: 'w', name: 'shop');

      expect(port.storedCookies.map((c) => c.name), ['sid']);
      expect(port.evaluatedSources.where((s) => s.contains('setItem')),
          isNotEmpty);
      expect(
        port.evaluatedSources.last,
        contains('theme'),
      );
    });

    test('PS3: missing name -> typed session_not_found, nothing applied',
        () async {
      await expectLater(
        sessions.load(webviewId: 'w', name: 'ghost'),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'session_not_found')),
      );
      expect(port.storedCookies, isEmpty);
      expect(port.evaluatedSources, isEmpty);
    });

    test('PS5: the setItem source is a JSON string literal for ordinary '
        'and hostile values', () async {
      const hostile = r"\');globalThis.__pwned='x';//";
      const values = <String, String>{
        'windowsPath': r'C:\Users\x',
        'escapedBackslash': r'a\nb',
        'realNewline': 'a\nb',
        'hostile': hostile,
      };
      await store.save(PortableSession(
        name: 'shop',
        origin: 'https://x.dev',
        localStorage: values,
      ));

      await sessions.load(webviewId: 'w', name: 'shop');

      final sources =
          port.evaluatedSources.where((s) => s.contains('setItem')).toList();
      expect(sources, hasLength(values.length));
      for (final entry in values.entries) {
        final literal = jsonEncode(entry.key);
        final source =
            sources.firstWhere((s) => s.contains(literal));
        // `jsonEncode` emits a valid JS literal, so the generated source
        // is byte-for-byte what it built — no hand-rolled escaper in play
        expect(
          source,
          'window.localStorage.setItem('
          '$literal, ${jsonEncode(entry.value)})',
        );
        expect(source, isNot(contains('\n')));
        expect(source, isNot(contains('\r')));
      }
    });

    test('PS5: a hostile value stays inert data inside its literal',
        () async {
      await store.save(PortableSession(
        name: 'evil',
        origin: 'https://x.dev',
        localStorage: {'k': r"\');globalThis.__pwned='x';//"},
      ));

      await sessions.load(webviewId: 'w', name: 'evil');

      const prefix = 'window.localStorage.setItem(';
      final source = port.evaluatedSources.last;
      expect(source, startsWith(prefix));
      expect(source, endsWith(')'));
      final args = source.substring(prefix.length, source.length - 1);
      final comma = args.indexOf(', ');
      expect(jsonDecode(args.substring(comma + 2)),
          r"\');globalThis.__pwned='x';//");
    });
  });

  group('US3 — hygiene', () {
    test('PS4: JSON round-trip + delete + list', () async {
      final session = PortableSession(
        name: 'shop',
        origin: 'https://x.dev',
        cookies: const [WebviewCookie(name: 'sid', value: '1')],
        localStorage: const {'theme': 'dark'},
        savedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final back = PortableSession.fromJson(session.toJson());
      expect(back.name, 'shop');
      expect(back.origin, 'https://x.dev');
      expect(back.cookies.single.name, 'sid');
      expect(back.localStorage['theme'], 'dark');
      // a fixed timestamp, so dropping `savedAtMs` from `toJson` cannot
      // pass by landing in the same clock millisecond
      expect(back.savedAt.millisecondsSinceEpoch, 1700000000000);

      await store.save(session);
      expect(await store.list(), ['shop']);
      await sessions.delete(name: 'shop');
      expect(await store.list(), isEmpty);
      expect(store.read('shop'), isNull);
    });
  });
}

/// In-memory store for tests (and a reference implementation of the
/// WebviewSessionStore port).
class MemorySessionStore implements WebviewSessionStore {
  final Map<String, PortableSession> _byName = {};

  @override
  Future<void> save(PortableSession session) async =>
      _byName[session.name] = session;

  @override
  PortableSession? read(String name) => _byName[name];

  @override
  Future<void> delete(String name) async => _byName.remove(name);

  @override
  Future<List<String>> list() async => _byName.keys.toList();
}

class _SessionsFakePort implements WebviewPort {
  final List<String> evaluatedSources = [];
  final List<WebviewCookie> storedCookies = [];
  Object? evaluateResult;
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
  }) async {}

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
  Future<void> setCookie(WebviewCookie cookie) async =>
      storedCookies.add(cookie);

  @override
  Future<bool> deleteCookie({
    required String url,
    required String name,
    String? domain,
    String path = '/',
  }) async =>
      false;

  @override
  Future<void> deleteAllCookies() async => storedCookies.clear();
}
