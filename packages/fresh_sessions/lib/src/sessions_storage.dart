import 'package:fresh_sessions/src/sessions_snapshot.dart';

/// Atomic persistence contract for the session registry.
///
/// Implementations must read/write the entire [SessionsSnapshot] atomically
/// to prevent split-state between the session list and the active session id.
abstract interface class SessionsStorage {
  /// Reads the persisted snapshot.
  ///
  /// Returns `null` when nothing has ever been stored (fresh install).
  /// Returns [SessionsSnapshot.empty] after an explicit
  /// [write] of an empty snapshot (e.g. after clearing all sessions).
  ///
  /// This distinction lets the controller decide whether to run
  /// legacy migration (only on `null`).
  Future<SessionsSnapshot?> read();

  /// Atomically persists the given [snapshot].
  Future<void> write(SessionsSnapshot snapshot);

  /// Removes all persisted session data.
  ///
  /// After this call, [read] returns `null` (same as fresh install).
  Future<void> clear();
}
