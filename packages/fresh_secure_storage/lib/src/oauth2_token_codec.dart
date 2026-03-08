import 'package:fresh/fresh.dart';

import 'package:fresh_secure_storage/src/token_codec.dart';

/// A built-in codec for [OAuth2Token].
final class OAuth2TokenCodec implements TokenCodec<OAuth2Token> {
  /// Creates an [OAuth2TokenCodec].
  const OAuth2TokenCodec();

  @override
  Map<String, Object?> encode(OAuth2Token token) {
    return <String, Object?>{
      'accessToken': token.accessToken,
      if (token.refreshToken != null) 'refreshToken': token.refreshToken,
      if (token.tokenType != null) 'tokenType': token.tokenType,
      if (token.expiresIn != null) 'expiresIn': token.expiresIn,
      if (token.scope != null) 'scope': token.scope,
      if (token.issuedAt != null) 'issuedAt': token.issuedAt!.toIso8601String(),
    };
  }

  @override
  OAuth2Token decode(Map<String, Object?> json) {
    final accessToken = _requireString(json, 'accessToken');
    return OAuth2Token(
      accessToken: accessToken,
      refreshToken: _readNullableString(json, 'refreshToken'),
      tokenType: _readNullableString(json, 'tokenType'),
      expiresIn: _readNullableInt(json, 'expiresIn'),
      scope: _readNullableString(json, 'scope'),
      issuedAt: _readNullableDateTime(json, 'issuedAt'),
    );
  }
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string.');
}

String? _readNullableString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string when present.');
}

int? _readNullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('Expected "$key" to be an int when present.');
}

DateTime? _readNullableDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Expected "$key" to be an ISO-8601 string.');
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Expected "$key" to contain a valid datetime.');
  }
  return parsed;
}
