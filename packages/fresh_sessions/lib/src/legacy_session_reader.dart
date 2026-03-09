import 'dart:async';

/// Result of reading a token from a legacy single-token storage.
final class LegacySessionResult<T> {
  /// Creates a [LegacySessionResult].
  const LegacySessionResult({
    required this.token,
    required this.userId,
    this.metadata = const {},
    this.cleanup,
  });

  /// The recovered token.
  final T token;

  /// The userId to assign to the migrated session.
  final String userId;

  /// Optional metadata to attach to the migrated session.
  final Map<String, Object?> metadata;

  /// Optional cleanup performed after the session is created
  /// (e.g. delete the old storage key).
  final FutureOr<void> Function()? cleanup;

  /// Runs any configured cleanup callback.
  Future<void> runCleanup() async {
    final cleanup = this.cleanup;
    if (cleanup == null) return;
    await Future<void>.value(cleanup());
  }
}

/// Reads a token from a legacy (pre-sessions) storage layout and
/// provides enough info to create a session from it.
// ignore: one_member_abstracts
abstract interface class LegacySessionReader<T> {
  /// Attempts to read a legacy token.
  ///
  /// Returns `null` when no legacy data is present.
  Future<LegacySessionResult<T>?> read();
}
