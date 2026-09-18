import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

    test(
      'D3/D4: the payload removes fixed/sticky overlays and resets the roots',
      () async {
        final dir = Directory.systemTemp.createTempSync('dialogue-dismiss');
        addTearDown(() => dir.deleteSync(recursive: true));
        final harness = File('${dir.path}/harness.js')
          ..writeAsStringSync(
            _harness.replaceFirst('__SCRIPT__', DialogueDismissScript.source),
          );

        final result = Process.runSync(_nodePath!, [harness.path]);
        expect(result.exitCode, 0, reason: 'node failed: ${result.stderr}');
        final out =
            jsonDecode(result.stdout as String) as Map<String, Object?>;

        expect(out['removed'], 2);
        expect(out['fixedRemoved'], isTrue);
        expect(out['stickyRemoved'], isTrue);
        expect(out['staticRemoved'], isFalse);
        // the roots started dirty and came back cleared, proving the
        // payload reset them rather than merely leaving them alone
        expect(out['rootOverflow'], '');
        expect(out['rootMargin'], '');
        expect(out['bodyOverflow'], '');
        expect(out['bodyMargin'], '');
      },
      skip: _nodePath == null ? 'node is not installed' : false,
    );
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

/// Behavioral harness (spec 002, US2): a minimal DOM — one `fixed`, one
/// `sticky` and one `static` node, plus roots whose overflow/margin start
/// dirty — for executing the payload under a real JS engine. A payload
/// with a wrong operator, an early `return` or a missing `remove()` fails
/// the assertions that read this output.
const String _harness = r'''
const elements = [
  {id: 'fixed', position: 'fixed', removed: false},
  {id: 'sticky', position: 'sticky', removed: false},
  {id: 'static', position: 'static', removed: false},
];
for (const el of elements) {
  el.remove = () => { el.removed = true; };
}
const documentElement = {style: {overflow: 'scroll', margin: 'scroll'}};
const body = {style: {overflow: 'hidden', margin: '8px'}};
const document = {
  querySelectorAll: () => elements,
  documentElement: documentElement,
  body: body,
};
const window = {getComputedStyle: (el) => ({position: el.position})};
const removed = __SCRIPT__;
console.log(JSON.stringify({
  removed: removed,
  fixedRemoved: elements[0].removed,
  stickyRemoved: elements[1].removed,
  staticRemoved: elements[2].removed,
  rootOverflow: documentElement.style.overflow,
  rootMargin: documentElement.style.margin,
  bodyOverflow: body.style.overflow,
  bodyMargin: body.style.margin,
}));
''';

/// `node`, or null when no engine is on PATH (the behavioral test skips).
final String? _nodePath = () {
  final which = Process.runSync('which', ['node']);
  if (which.exitCode != 0) return null;
  return (which.stdout as String).trim();
}();
