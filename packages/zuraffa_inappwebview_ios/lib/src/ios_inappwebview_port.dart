import 'dart:typed_data';

import 'package:zuraffa_inappwebview/zuraffa_inappwebview.dart';

import 'ios_inappwebview_channel.dart';
import 'ios_inappwebview_exception.dart';

/// iOS [InappwebviewPort] over the typed
/// [IosInappwebviewChannel].
class IosInappwebviewPort implements InappwebviewPort {
  final IosInappwebviewChannel channel;

  const IosInappwebviewPort({required this.channel});

  @override
  Future<bool> isSupported() async {
    final result = await channel.call('isSupported', const {});
    return result?['supported'] == true;
  }

  @override
  Future<InappwebviewModule> compile({
    required String id,
    required Uint8List bytes,
  }) async {
    final result = await channel.call('compile', {
      'id': id,
      'bytes': bytes,
    });
    return InappwebviewModule(
      id: id,
      byteLength:
          (result?['byteLength'] as num?)?.toInt() ?? bytes.lengthInBytes,
    );
  }

  @override
  Future<List<InappwebviewValue>> invoke({
    required String id,
    required String export,
    List<InappwebviewValue> args = const [],
  }) async {
    final result = await channel.call('invoke', {
      'id': id,
      'export': export,
      'args': [for (final arg in args) arg.encode()],
    });
    final values = result?['values'];
    if (values is! List) {
      throw const IosInappwebviewException(
        'malformed_response',
        'The invoke result carried no value list.',
        recoverable: false,
      );
    }
    return [for (final raw in values) InappwebviewValue.decode(raw)];
  }

  @override
  Future<void> unload({required String id}) async {
    await channel.call('unload', {'id': id});
  }
}
