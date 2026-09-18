import 'dart:async';

import 'package:test/test.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

/// Fake port that records every evaluated JS source (per id) and can be
/// scripted to raise during evaluation.
class RecordingWebviewPort implements WebviewPort {
  final List<(String id, String source)> evaluated = [];
  Object? Function(String source)? evaluateHook;

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
  }) async {
    evaluated.add((id, source));
    final hook = evaluateHook;
    if (hook != null) {
      return hook(source);
    }
    return null;
  }

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
  Future<void> loadHtml({
    required String id,
    required String html,
    String? baseUrl,
  }) async {}

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

void main() {
  late RecordingWebviewPort port;
  late WebviewService service;

  setUp(() async {
    port = RecordingWebviewPort();
    service = WebviewService(port: port);
    await service.createHeadless(id: 'scraper');
  });

  group('US1 — typed setting', () {
    test('D1: default is off and serialized', () {
      expect(WebviewSettings().toChannelArgs()['dismissDialogues'], isFalse);
    });

    test('D2: opted-in flag serializes', () {
      expect(
        const WebviewSettings(dismissDialogues: true)
            .toChannelArgs()['dismissDialogues'],
        isTrue,
      );
    });
  });

  group('US2 — canonical script', () {
    final source = DialogueDismissScript.source;

    test('D3: removes computed fixed/sticky elements', () {
      expect(source, contains('getComputedStyle'));
      expect(source, contains('fixed'));
      expect(source, contains('sticky'));
      expect(source, contains('.remove()'));
      // The exact condition is pinned: a substring test alone would accept
      // a no-op dismisser (`pos === "fixed" && pos === "sticky"`).
      expect(source, contains("pos === 'fixed' || pos === 'sticky'"));
    });

    test('D3b: the document roots are never removed', () {
      expect(
        source,
        contains(
          'if (el === document.documentElement || el === document.body) '
          'continue;',
        ),
      );
    });

    test('D4: resets overflow/margin on documentElement and body', () {
      expect(source, contains('documentElement'));
      expect(source, contains('body'));
      expect(source, contains('overflow'));
      expect(source, contains('margin'));
    });

    test('D5: top-level document only (no frames recursion)', () {
      expect(source, isNot(contains('frames')));
      expect(source, isNot(contains('iframe')));
      expect(source, isNot(contains('contentWindow')));
    });
  });

  group('US3 — policy', () {
    test('D6: attempts clamp to >= 1; defaults 1 attempt, zero delay', () {
      const policy = DialogueDismissPolicy(attempts: 0);
      expect(policy.attempts, 1);
      expect(const DialogueDismissPolicy().attempts, 1);
      expect(const DialogueDismissPolicy().delay, Duration.zero);
    });
  });

  group('service facade', () {
    test('D7: one canonical evaluation per default call', () async {
      await service.dismissDialogues(id: 'scraper');
      expect(port.evaluated, hasLength(1));
      expect(port.evaluated.single, ('scraper', DialogueDismissScript.source));
    });

    test('D8: unknown id -> typed not_created', () {
      expect(
        () => service.dismissDialogues(id: 'nope'),
        throwsA(
          isA<WebviewException>().having(
            (e) => e.code,
            'code',
            'not_created',
          ),
        ),
      );
    });

    test('D9: port errors during dismissal are swallowed', () async {
      port.evaluateHook = (_) => throw const WebviewException(
            'javascript_failed',
            'boom',
            recoverable: true,
          );
      await service.dismissDialogues(id: 'scraper');
      expect(port.evaluated, hasLength(1));
    });

    test('D9: non-Exception errors are swallowed as well', () async {
      // A mis-wired port throws Error subclasses (StateError/TypeError),
      // which the previous `on Exception` guard let through.
      port.evaluateHook = (_) => throw StateError('mis-wired port');
      await service.dismissDialogues(id: 'scraper');
      expect(port.evaluated, hasLength(1));
    });

    test('D10: attempts drive repeated evaluations with delay', () async {
      const policy = DialogueDismissPolicy(
        attempts: 3,
        delay: Duration(milliseconds: 5),
      );
      await service.dismissDialogues(id: 'scraper', policy: policy);
      expect(port.evaluated, hasLength(3));
      expect(
        port.evaluated.every((e) => e.$2 == DialogueDismissScript.source),
        isTrue,
      );
    });
  });
}
