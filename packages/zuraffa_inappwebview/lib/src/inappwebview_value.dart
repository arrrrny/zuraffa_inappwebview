import 'inappwebview_exception.dart';

/// A WebAssembly scalar value crossing the platform boundary.
///
/// The scaffold ships the four numeric types; the migration extends the
/// family (reference types, vectors) without breaking the contract.
sealed class InappwebviewValue {
  const InappwebviewValue();

  /// Encodes this value into the primitive representation transported over
  /// the platform channel. i64 travels as a decimal string — channel
  /// payloads cannot carry a BigInt losslessly.
  Object encode() => switch (this) {
        InappwebviewI32(:final value) => value,
        InappwebviewI64(:final value) => value.toString(),
        InappwebviewF32(:final value) => value,
        InappwebviewF64(:final value) => value,
      };

  /// Decodes a channel payload into a [InappwebviewValue]: ints decode as
  /// i32, doubles as f64, and decimal strings as i64.
  static InappwebviewValue decode(Object? raw) {
    if (raw is int) return InappwebviewI32(raw);
    if (raw is double) return InappwebviewF64(raw);
    if (raw is String) {
      final parsed = BigInt.tryParse(raw);
      if (parsed != null) return InappwebviewI64(parsed);
    }
    throw InappwebviewException(
      'malformed_value',
      'Cannot decode "$raw" into a InappwebviewValue.',
      recoverable: false,
    );
  }
}

/// A 32-bit integer value.
class InappwebviewI32 extends InappwebviewValue {
  final int value;

  const InappwebviewI32(this.value);
}

/// A 64-bit integer value (transported as a decimal string).
class InappwebviewI64 extends InappwebviewValue {
  final BigInt value;

  const InappwebviewI64(this.value);
}

/// A 32-bit float value.
class InappwebviewF32 extends InappwebviewValue {
  final double value;

  const InappwebviewF32(this.value);
}

/// A 64-bit float value.
class InappwebviewF64 extends InappwebviewValue {
  final double value;

  const InappwebviewF64(this.value);
}
