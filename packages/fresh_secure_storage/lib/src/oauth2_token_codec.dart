import 'package:fresh/fresh.dart';

import 'package:fresh_secure_storage/src/token_codec.dart';

/// A built-in codec for [OAuth2Token].
final class OAuth2TokenCodec implements TokenCodec<OAuth2Token> {
  /// Creates an [OAuth2TokenCodec].
  const OAuth2TokenCodec();

  @override
  Map<String, Object?> encode(OAuth2Token token) => token.toJson();

  @override
  OAuth2Token decode(Map<String, Object?> json) => OAuth2Token.fromJson(json);
}
