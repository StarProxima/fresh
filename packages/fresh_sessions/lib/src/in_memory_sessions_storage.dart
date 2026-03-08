import 'package:fresh_sessions/src/sessions_snapshot.dart';
import 'package:fresh_sessions/src/sessions_storage.dart';

/// A [SessionsStorage] implementation that keeps the snapshot in memory.
///
/// Useful for testing and scenarios where session persistence across
/// app restarts is not required.
final class InMemorySessionsStorage implements SessionsStorage {
  SessionsSnapshot _snapshot = SessionsSnapshot.empty;

  @override
  Future<SessionsSnapshot> read() async => _snapshot;

  @override
  Future<void> write(SessionsSnapshot snapshot) async {
    _snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    _snapshot = SessionsSnapshot.empty;
  }
}
