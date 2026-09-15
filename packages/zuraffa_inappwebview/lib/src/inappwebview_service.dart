import 'dart:typed_data';

import 'package:zuraffa/zuraffa.dart';

import 'inappwebview_exception.dart';
import 'inappwebview_module.dart';
import 'inappwebview_port.dart';
import 'inappwebview_value.dart';

/// Facade over the [InappwebviewPort]: owns the compiled-module registry
/// and turns lifecycle mistakes (double compile, call-before-compile)
/// into typed failures before they reach the platform.
class InappwebviewService {
  final InappwebviewPort port;
  final Map<String, InappwebviewModule> _modules = {};

  InappwebviewService({required this.port});

  /// The compiled modules currently held by this service.
  Set<String> get compiledModules => Set.unmodifiable(_modules.keys);

  Future<bool> supported() => port.isSupported();

  Future<InappwebviewModule> compile({
    required String id,
    required Uint8List bytes,
  }) async {
    if (_modules.containsKey(id)) {
      throw InappwebviewException(
        'already_compiled',
        'Module "$id" is already compiled — unload it first.',
        recoverable: false,
      );
    }
    final module = await port.compile(id: id, bytes: bytes);
    _modules[id] = module;
    return module;
  }

  Future<List<InappwebviewValue>> call({
    required String id,
    required String export,
    List<InappwebviewValue> args = const [],
  }) async {
    _requireCompiled(id);
    return port.invoke(id: id, export: export, args: args);
  }

  Future<void> unload({required String id}) async {
    _requireCompiled(id);
    await port.unload(id: id);
    _modules.remove(id);
  }

  void _requireCompiled(String id) {
    if (!_modules.containsKey(id)) {
      throw InappwebviewException(
        'not_compiled',
        'Module "$id" is not compiled — call compile() first.',
        recoverable: false,
      );
    }
  }
}

/// A port placeholder registered when no platform adapter was wired:
/// every operation surfaces the typed `port_not_wired` failure instead of
/// a null dereference at resolve time.
class _UnwiredInappwebviewPort implements InappwebviewPort {
  const _UnwiredInappwebviewPort();

  Never _unwired() => throw const InappwebviewException(
        'port_not_wired',
        'No InappwebviewPort was registered — wire the platform adapter '
        'for the running platform before resolving InappwebviewService.',
        recoverable: false,
      );

  @override
  Future<bool> isSupported() async => _unwired();

  @override
  Future<InappwebviewModule> compile({
    required String id,
    required Uint8List bytes,
  }) =>
      _unwired();

  @override
  Future<List<InappwebviewValue>> invoke({
    required String id,
    required String export,
    List<InappwebviewValue> args = const [],
  }) =>
      _unwired();

  @override
  Future<void> unload({required String id}) => _unwired();
}

/// Registers the zuraffa_inappwebview stack onto [getIt]: the [InappwebviewPort] is
/// normally supplied by the platform adapter package for the running
/// platform (e.g. `registerAndroidInappwebviewDependencies`), so the
/// service falls back to the GetIt-registered port when no explicit one
/// is passed. Without any registered port the service resolves over the
/// unwired placeholder and surfaces typed `port_not_wired` failures.
void registerInappwebviewDependencies(
  GetIt getIt, {
  InappwebviewPort? port,
}) {
  getIt.registerLazySingleton<InappwebviewService>(
    () => InappwebviewService(
      port:
          port ??
          (getIt.isRegistered<InappwebviewPort>()
              ? getIt<InappwebviewPort>()
              : const _UnwiredInappwebviewPort()),
    ),
  );
}
