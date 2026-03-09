import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:fresh_sessions/src/fresh_session.dart';
import 'package:fresh_sessions/src/fresh_session_controller_base.dart';
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
    SessionIdBuilder? sessionIdBuilder,
  })  : _sessionsStorage = sessionsStorage,
        _tokenStorageBuilder = tokenStorageBuilder,
        _freshBuilder = freshBuilder,
        _sessionIdBuilder = sessionIdBuilder ?? _defaultSessionIdBuilder {
    _ready = _hydrate();
  }

  final SessionsStorage _sessionsStorage;
  final TokenStorageBuilder<T> _tokenStorageBuilder;
  final FreshBuilder<F, T> _freshBuilder;
  final SessionIdBuilder _sessionIdBuilder;

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
  Future<FreshSession> createSession({
    required T token,
    required String userId,
    String? environment,
    bool makeActive = true,
  }) async {
    _assertNotClosed();
    final id = _sessionIdBuilder(userId, environment);
    final now = DateTime.now();

    final existing = _findSession(id);

    final record = existing?.copyWith(updatedAt: now) ??
        FreshSession(
          id: id,
          userId: userId,
          environment: environment,
          createdAt: now,
          updatedAt: now,
        );

    await _tokenStorageBuilder(id).write(token);

    final sessions = existing != null
        ? [
            for (final s in _snapshot.sessions)
              if (s.id == id) record else s,
          ]
        : [..._snapshot.sessions, record];

    if (makeActive) {
      await _updateSnapshot(
        _snapshot.copyWith(
          sessions: sessions,
          activeSessionId: () => id,
        ),
      );
      await _rebuildFresh(id);
    } else {
      await _updateSnapshot(
        _snapshot.copyWith(sessions: sessions),
      );
    }

    return record;
  }

  @override
  Future<void> setActiveSession(FreshSession session) async {
    _assertNotClosed();
    if (_findSession(session.id) == null) {
      throw StateError(
        'Session ${session.id} not found in registry',
      );
    }

    await _updateSnapshot(
      _snapshot.copyWith(activeSessionId: () => session.id),
    );
    await _rebuildFresh(session.id);
  }

  @override
  Future<void> removeSession([FreshSession? session]) async {
    _assertNotClosed();
    final sessionId = session?.id ?? _snapshot.activeSessionId;

    if (sessionId == null) {
      throw StateError(
        'No session to remove',
      );
    }

    final wasActive = _snapshot.activeSessionId == sessionId;

    final sessions = [
      for (final s in _snapshot.sessions)
        if (s.id != sessionId) s,
    ];

    if (wasActive) {
      await _closeFresh();
      await _updateSnapshot(
        _snapshot.copyWith(
          sessions: sessions,
          activeSessionId: () => null,
        ),
      );
      _emitFresh(null);
    } else {
      await _updateSnapshot(
        _snapshot.copyWith(sessions: sessions),
      );
    }

    await _tokenStorageBuilder(sessionId).delete();
  }

  @override
  Future<void> clearAllSessions() async {
    _assertNotClosed();
    final sessionIds = _snapshot.sessions.map((s) => s.id).toList();

    await _closeFresh();
    await _updateSnapshot(SessionsSnapshot.empty);
    _emitFresh(null);

    for (final id in sessionIds) {
      await _tokenStorageBuilder(id).delete();
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
    _snapshot = await _sessionsStorage.read();
    _snapshotController.add(_snapshot);

    final activeId = _snapshot.activeSessionId;
    if (activeId != null && _findSession(activeId) != null) {
      await _rebuildFresh(activeId);
    } else {
      _emitFresh(null);
    }
  }

  Future<void> _updateSnapshot(SessionsSnapshot snapshot) async {
    _snapshot = snapshot;
    await _sessionsStorage.write(snapshot);
    _snapshotController.add(snapshot);
  }

  Future<void> _rebuildFresh(String sessionId) async {
    await _closeFresh();
    _fresh = _freshBuilder(_tokenStorageBuilder(sessionId));
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

  FreshSession? _findSession(String id) {
    for (final s in _snapshot.sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _assertNotClosed() {
    if (_closed) {
      throw StateError(
        'FreshSessionController has been closed',
      );
    }
  }

  static String _defaultSessionIdBuilder(
    String userId,
    String? environment,
  ) =>
      environment != null ? '$userId@$environment' : userId;
}
