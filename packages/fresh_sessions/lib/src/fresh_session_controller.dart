import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:fresh_sessions/src/fresh_session.dart';
import 'package:fresh_sessions/src/fresh_session_controller_base.dart';
import 'package:fresh_sessions/src/legacy_session_reader.dart';
import 'package:fresh_sessions/src/sessions_snapshot.dart';
import 'package:fresh_sessions/src/sessions_storage.dart';

/// {@macro fresh_session_controller}
final class FreshSessionController<F extends FreshMixin<T>, T>
    implements FreshSessionControllerBase<F, T> {
  /// {@macro fresh_session_controller}
  FreshSessionController({
    required SessionsStorage sessionsStorage,
    required TokenStorageBuilder<T> tokenStorageBuilder,
    required FreshBuilder<F, T> freshBuilder,
    List<LegacySessionReader<T>> legacySessionReaders = const [],
  })  : _sessionsStorage = sessionsStorage,
        _tokenStorageBuilder = tokenStorageBuilder,
        _freshBuilder = freshBuilder,
        _legacySessionReaders =
            List<LegacySessionReader<T>>.unmodifiable(legacySessionReaders) {
    _ready = _hydrate();
  }

  final SessionsStorage _sessionsStorage;
  final TokenStorageBuilder<T> _tokenStorageBuilder;
  final FreshBuilder<F, T> _freshBuilder;
  final List<LegacySessionReader<T>> _legacySessionReaders;

  late final Future<void> _ready;
  bool _closed = false;

  SessionsSnapshot _snapshot = SessionsSnapshot.empty;
  F? _fresh;

  final _snapshotController = StreamController<SessionsSnapshot>.broadcast();
  final _freshController = StreamController<F?>.broadcast();

  @override
  Future<void> get ready => _ready;

  @override
  SessionsSnapshot get snapshot => _snapshot;

  @override
  FreshSession? get activeSession => _snapshot.activeSession;

  @override
  F? get fresh => _fresh;

  @override
  Stream<SessionsSnapshot> get snapshotStream => _snapshotController.stream;

  @override
  Stream<FreshSession?> get activeSessionStream =>
      snapshotStream.map((s) => s.activeSession).distinct();

  @override
  Stream<FreshSession> get activeSessionChangedStream =>
      activeSessionStream.where((s) => s != null).cast<FreshSession>();

  @override
  Stream<F?> get freshStream => _freshController.stream;

  @override
  Future<FreshSession> saveSession({
    required T token,
    required String userId,
    Map<String, Object?> metadata = const {},
    bool makeActive = true,
  }) async {
    _assertNotClosed();
    final now = DateTime.now();

    final existing = _findSession(userId);

    final record = existing?.copyWith(updatedAt: now, metadata: metadata) ??
        FreshSession(
          userId: userId,
          createdAt: now,
          updatedAt: now,
          metadata: metadata,
        );

    await _tokenStorageBuilder(record).write(token);

    final sessions = existing != null
        ? [
            for (final s in _snapshot.sessions)
              if (s.userId == userId) record else s,
          ]
        : [..._snapshot.sessions, record];

    if (makeActive) {
      await _updateSnapshot(
        _snapshot.copyWith(
          sessions: sessions,
          activeUserId: () => userId,
        ),
      );
      await _rebuildFresh(record);
    } else {
      await _updateSnapshot(
        _snapshot.copyWith(sessions: sessions),
      );
    }

    return record;
  }

  @override
  Future<T?> readToken(FreshSession session) {
    return _tokenStorageBuilder(session).read();
  }

  @override
  Future<void> setActiveSession(FreshSession session) async {
    _assertNotClosed();
    if (_findSession(session.userId) == null) {
      throw StateError(
        'Session for user ${session.userId} not found in registry',
      );
    }

    await _updateSnapshot(
      _snapshot.copyWith(activeUserId: () => session.userId),
    );
    await _rebuildFresh(session);
  }

  @override
  Future<void> removeSession([FreshSession? session]) async {
    _assertNotClosed();
    final targetUserId = session?.userId ?? _snapshot.activeUserId;

    if (targetUserId == null) {
      throw StateError('No session to remove');
    }

    final targetSession = _findSession(targetUserId);
    if (targetSession == null) {
      throw StateError(
        'Session for user $targetUserId not found in registry',
      );
    }

    final wasActive = _snapshot.activeUserId == targetUserId;

    final sessions = [
      for (final s in _snapshot.sessions)
        if (s.userId != targetUserId) s,
    ];

    if (wasActive) {
      await _closeFresh();
      await _updateSnapshot(
        _snapshot.copyWith(
          sessions: sessions,
          activeUserId: () => null,
        ),
      );
      _emitFresh(null);
    } else {
      await _updateSnapshot(
        _snapshot.copyWith(sessions: sessions),
      );
    }

    await _tokenStorageBuilder(targetSession).delete();
  }

  @override
  Future<void> clearAllSessions() async {
    _assertNotClosed();
    final sessions = _snapshot.sessions.toList();

    await _closeFresh();
    await _updateSnapshot(SessionsSnapshot.empty);
    _emitFresh(null);

    for (final session in sessions) {
      await _tokenStorageBuilder(session).delete();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _closeFresh();
    await _snapshotController.close();
    await _freshController.close();
  }

  // ---------------------------------------------------------
  // Internal
  // ---------------------------------------------------------

  Future<void> _hydrate() async {
    final stored = await _sessionsStorage.read();
    _snapshot = stored ?? SessionsSnapshot.empty;

    if (stored == null) {
      await _migrateLegacy();
    }

    _snapshotController.add(_snapshot);

    final activeSession = _snapshot.activeSession;
    if (activeSession != null) {
      await _rebuildFresh(activeSession);
    } else {
      _emitFresh(null);
    }
  }

  Future<void> _migrateLegacy() async {
    for (final reader in _legacySessionReaders) {
      try {
        final result = await reader.read();
        if (result == null) continue;

        await saveSession(
          token: result.token,
          userId: result.userId,
          metadata: result.metadata,
        );
        await result.runCleanup();
      } catch (_) {
        // Skip broken legacy entries silently.
      }
    }
  }

  Future<void> _updateSnapshot(SessionsSnapshot snapshot) async {
    _snapshot = snapshot;
    await _sessionsStorage.write(snapshot);
    _snapshotController.add(snapshot);
  }

  Future<void> _rebuildFresh(FreshSession session) async {
    await _closeFresh();
    _fresh = _freshBuilder(_tokenStorageBuilder(session));
    _emitFresh(_fresh);
  }

  Future<void> _closeFresh() async {
    final current = _fresh;
    _fresh = null;
    if (current != null) {
      await current.close();
    }
  }

  void _emitFresh(F? fresh) {
    if (!_freshController.isClosed) {
      _freshController.add(fresh);
    }
  }

  FreshSession? _findSession(String userId) {
    for (final s in _snapshot.sessions) {
      if (s.userId == userId) return s;
    }
    return null;
  }

  void _assertNotClosed() {
    if (_closed) {
      throw StateError('FreshSessionController has been closed');
    }
  }
}
