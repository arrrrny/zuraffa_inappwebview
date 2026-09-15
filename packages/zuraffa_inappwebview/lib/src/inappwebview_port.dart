import 'dart:typed_data';

import 'inappwebview_module.dart';
import 'inappwebview_value.dart';

/// The platform-neutral port every adapter implements. Pure Dart — the
/// transport is injected behind the platform envelope, so tests run
/// offline with fake channels.
abstract class InappwebviewPort {
  const InappwebviewPort();

  /// Whether the host platform can run WebAssembly at all.
  Future<bool> isSupported();

  /// Compiles [bytes] and binds the result to [id].
  Future<InappwebviewModule> compile({
    required String id,
    required Uint8List bytes,
  });

  /// Invokes [export] on the compiled module [id].
  Future<List<InappwebviewValue>> invoke({
    required String id,
    required String export,
    List<InappwebviewValue> args = const [],
  });

  /// Releases the compiled module [id].
  Future<void> unload({required String id});
}
