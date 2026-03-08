/// Converts tokens to and from JSON-safe maps for secure storage.
abstract interface class TokenCodec<T> {
  /// Encodes a token into a JSON-safe payload.
  Map<String, Object?> encode(T token);

  /// Decodes a token from a JSON-safe payload.
  T decode(Map<String, Object?> json);
}
