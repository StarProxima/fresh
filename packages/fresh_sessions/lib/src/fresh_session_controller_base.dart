import 'package:fresh/fresh.dart';
import 'package:fresh_sessions/src/fresh_session.dart';
import 'package:fresh_sessions/src/sessions_snapshot.dart';

/// Builds a deterministic session id from user identity and
/// optional environment.
typedef SessionIdBuilder = String Function(
  String userId,
  String? environment,
);

/// Builds a [TokenStorage] scoped to a specific session by its
/// [sessionId].
typedef TokenStorageBuilder<T> = TokenStorage<T> Function(
  String sessionId,
);

/// Builds a concrete [FreshMixin] instance using the provided
/// [tokenStorage].
typedef FreshBuilder<F extends FreshMixin<T>, T> = F Function(
  TokenStorage<T> tokenStorage,
);

/// {@template fresh_session_controller}
/// Multi-session orchestration facade for `fresh`.
///
/// Manages a registry of sessions ([SessionsSnapshot]), tracks
/// which one is currently active, and controls the lifecycle of
/// the associated [FreshMixin] instance.
///
/// Tokens are **never** stored inside the session registry.
/// Token lifecycle is fully delegated to [TokenStorage] instances
/// produced by [TokenStorageBuilder].
///
/// Switching the active session always produces a new [FreshMixin]
/// instance because `FreshMixin` caches the in-memory token and
/// the in-flight refresh future internally and cannot be safely
/// reused across different sessions.
/// {@endtemplate}
abstract interface class FreshSessionControllerBase<F extends FreshMixin<T>,
    T> {
  /// Completes when the controller has finished reading persisted
  /// state and (if an active session exists) built the initial
  /// [FreshMixin] instance.
  ///
  /// Must be awaited before accessing [snapshot], [activeSession],
  /// or [fresh].
  Future<void> get ready;

  /// The current session registry snapshot.
  SessionsSnapshot get snapshot;

  /// The currently active [FreshSession], or `null` if no session
  /// is selected.
  FreshSession? get activeSession;

  /// The [FreshMixin] instance bound to the active session,
  /// or `null` when there is no active session.
  F? get fresh;

  /// Emits a new [SessionsSnapshot] every time the session registry
  /// is mutated (create / remove / switch / clear).
  Stream<SessionsSnapshot> get snapshotStream;

  /// Emits the active [FreshSession] (or `null`) whenever the
  /// active session changes. Derived from [snapshotStream].
  Stream<FreshSession?> get activeSessionStream;

  /// Emits a non-null [FreshSession] only when the active session
  /// switches to a different session. Does not emit on clear/logout
  /// (when active becomes `null`).
  Stream<FreshSession> get activeSessionChangedStream;

  /// Emits the current [FreshMixin] instance (or `null`) whenever
  /// it is rebuilt or cleared due to a session switch.
  Stream<F?> get freshStream;

  /// Creates a new session, writes the initial [token] to its
  /// [TokenStorage], and optionally makes it the active session.
  ///
  /// If a session with the same id already exists, its metadata
  /// is updated and the token is overwritten.
  ///
  /// When [makeActive] is `true` (default), the new session becomes
  /// active immediately and a new [FreshMixin] instance is built.
  ///
  /// Returns the created (or updated) [FreshSession].
  Future<FreshSession> createSession({
    required T token,
    required String userId,
    String? environment,
    bool makeActive = true,
  });

  /// Switches the active session to [session].
  ///
  /// The previous [FreshMixin] instance is closed and a new one is
  /// built with a [TokenStorage] scoped to the given session.
  ///
  /// Throws [StateError] if [session] is not in the registry.
  Future<void> setActiveSession(FreshSession session);

  /// Removes [session] from the registry and deletes its token
  /// storage.
  ///
  /// If [session] was the active one, the active session and the
  /// [FreshMixin] instance are cleared (set to `null`).
  /// If [session] is `null`, the active session is removed.
  Future<void> removeSession([FreshSession? session]);

  /// Removes **all** sessions and deletes every associated token
  /// storage entry.
  Future<void> clearAllSessions();

  /// Closes all streams and the current [FreshMixin] instance.
  ///
  /// The controller must not be used after this call.
  Future<void> close();
}
