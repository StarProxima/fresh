import 'dart:async';
import 'dart:convert';

import 'package:fresh_secure_storage/src/token_codec.dart';

/// Result of a successful legacy token read.
final class LegacyReadResult<T> {
  /// Creates a [LegacyReadResult].
  const LegacyReadResult({
    required this.token,
    this.cleanup,
  });

  /// The recovered token.
  final T token;

  /// Optional cleanup performed after the token is rewritten.
  final FutureOr<void> Function()? cleanup;

  /// Runs any configured cleanup callback.
  Future<void> runCleanup() async {
    final cleanup = this.cleanup;
    if (cleanup == null) return;
    await Future<void>.value(cleanup());
  }
}

/// Reads tokens from older storage layouts.
// ignore: one_member_abstracts
abstract interface class LegacyTokenReader<T> {
  /// Attempts to read a legacy token.
  ///
  /// Returns `null` when the legacy layout is not present.
  Future<LegacyReadResult<T>?> read();
}

/// Reads a legacy JSON token stored without a versioned envelope.
final class JsonLegacyTokenReader<T> implements LegacyTokenReader<T> {
  /// Creates a [JsonLegacyTokenReader].
  JsonLegacyTokenReader({
    required Future<String?> Function() read,
    required TokenCodec<T> codec,
    FutureOr<void> Function()? cleanup,
  })  : _read = read,
        _codec = codec,
        _cleanup = cleanup;

  final Future<String?> Function() _read;
  final TokenCodec<T> _codec;
  final FutureOr<void> Function()? _cleanup;

  @override
  Future<LegacyReadResult<T>?> read() async {
    final rawValue = await _read();
    if (rawValue == null) return null;

    final decodedValue = jsonDecode(rawValue);
    if (decodedValue is! Map<Object?, Object?>) {
      throw const FormatException(
        'Legacy token payload must decode to a JSON object.',
      );
    }

    final token = _codec.decode(_castJsonMap(decodedValue));

    return LegacyReadResult<T>(
      token: token,
      cleanup: _cleanup,
    );
  }
}

Map<String, Object?> _castJsonMap(Map<Object?, Object?> value) {
  return Map<String, Object?>.from(value);
}
