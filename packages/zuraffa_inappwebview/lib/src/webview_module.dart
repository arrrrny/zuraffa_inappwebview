import 'package:zuraffa/zuraffa.dart';

import 'webview_port.dart';
import 'webview_service.dart';
import 'webview_usecases.dart';

/// Registers the webview service and usecases into [di]. Nothing already
/// registered is overridden — wire a platform adapter's [WebviewPort] first
/// (see `registerAndroidWebviewDependencies` etc.) and the module defers
/// to it; otherwise the service resolves over the unwired port and every
/// call surfaces the typed `port_not_wired` failure.
void registerWebview(ZuraffaDIContainer di) {
  if (!di.getIt.isRegistered<WebviewPort>()) {
    di.getIt.registerLazySingleton<WebviewPort>(
        () => const UnwiredWebviewPort());
  }
  if (!di.getIt.isRegistered<WebviewService>()) {
    di.getIt
        .registerLazySingleton<WebviewService>(() => WebviewService(
              port: di.getIt<WebviewPort>(),
            ));
  }
  if (!di.getIt.isRegistered<LoadUrlUseCase>()) {
    di.getIt.registerFactory<LoadUrlUseCase>(
        () => LoadUrlUseCase(service: di.getIt<WebviewService>()));
  }
  if (!di.getIt.isRegistered<EvaluateJavascriptUseCase>()) {
    di.getIt.registerFactory<EvaluateJavascriptUseCase>(
        () => EvaluateJavascriptUseCase(service: di.getIt<WebviewService>()));
  }
  if (!di.getIt.isRegistered<SetCookieUseCase>()) {
    di.getIt.registerFactory<SetCookieUseCase>(
        () => SetCookieUseCase(service: di.getIt<WebviewService>()));
  }
}

/// Zuraffa runtime module for zuraffa_inappwebview.
///
/// Contributes the webview service and usecases to the consuming app's
/// container (auto-DI). Wire the running platform's adapter first:
///
/// ```dart
/// final engine = ZuraffaEngine()
///   ..registerPackage(DarwinWebviewModule())   // or AndroidWebviewModule()
///   ..registerPackage(WebviewModule());
/// await engine.bootstrap();
///
/// await engine.di.get<LoadUrlUseCase>()(LoadUrlParams(
///   webviewId: 'scraper',
///   url: WebviewUri('https://example.org'),
/// ));
/// ```
class WebviewModule extends PackageModule {
  @override
  String get pluginId => 'zuraffa_inappwebview';

  @override
  String get zuraffaSdkConstraint => '^6.3.0';

  @override
  Map<String, ZuraffaRouteHandler> get routes => const {};

  @override
  void registerDependencies(ZuraffaDIContainer di) => registerWebview(di);
}
