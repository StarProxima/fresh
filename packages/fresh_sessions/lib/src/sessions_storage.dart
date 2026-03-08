import 'package:fresh_sessions/src/sessions_snapshot.dart';

/// Atomic persistence contract for the session registry.
///
/// Implementations must read/write the entire [SessionsSnapshot] atomically
/// to prevent split-state between the session list and the active session id.
abstract interface class SessionsStorage {
  /// Reads the persisted snapshot, returning [SessionsSnapshot.empty] if
  /// nothing has been stored yet.
  Future<SessionsSnapshot> read();

  /// Atomically persists the given [snapshot].
  Future<void> write(SessionsSnapshot snapshot);

  /// Removes all persisted session data.
  Future<void> clear();
}
