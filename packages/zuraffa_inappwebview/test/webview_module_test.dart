import 'package:test/test.dart';
import 'package:zuraffa/zuraffa.dart';
import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'webview_service_test.dart' show FakeWebviewPort;

void main() {
  group('WebviewModule / registerWebview (W15-W17)', () {
    late ZuraffaDIContainer di;

    setUp(() async {
      await GetIt.I.reset();
      di = ZuraffaDIContainer();
    });

    tearDown(() async {
      await GetIt.I.reset();
    });

    test('W15: registers the unwired port by default; calls fail typed',
        () async {
      registerWebview(di);

      expect(di.getIt.isRegistered<WebviewPort>(), isTrue);
      expect(di.getIt.isRegistered<WebviewService>(), isTrue);
      expect(di.getIt.isRegistered<LoadUrlUseCase>(), isTrue);

      // The unwired default surfaces the typed failure, not a crash.
      await expectLater(
        di.getIt<WebviewService>().supported(),
        throwsA(isA<WebviewException>()
            .having((e) => e.code, 'code', 'port_not_wired')),
      );
    });

    test('W16: a pre-registered port is never overridden', () async {
      final fake = FakeWebviewPort();
      di.getIt.registerSingleton<WebviewPort>(fake);

      registerWebview(di);

      expect(di.getIt<WebviewPort>(), same(fake));
      expect(di.getIt<WebviewService>().port, same(fake));
    });

    test('W17: module registration contributes the same registrations',
        () async {
      final fake = FakeWebviewPort();
      di.getIt.registerSingleton<WebviewPort>(fake);

      final module = WebviewModule();
      expect(module.pluginId, 'zuraffa_inappwebview');
      module.registerDependencies(di);

      expect(di.getIt.isRegistered<SetCookieUseCase>(), isTrue);
      expect(di.getIt<LoadUrlUseCase>().service.port, same(fake));
    });
  });
}
