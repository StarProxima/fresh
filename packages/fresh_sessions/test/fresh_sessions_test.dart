import 'dart:async';

import 'package:fresh/fresh.dart';
import 'package:fresh_sessions/fresh_sessions.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _MockSessionsStorage extends Mock implements SessionsStorage {}

class _TestFresh with FreshMixin<String> {
  _TestFresh(TokenStorage<String> tokenStorage) {
    this.tokenStorage = tokenStorage;
  }

  @override
  Future<String> performTokenRefresh(String? token) async => '${token}_new';
}

class _TokenStorageRegistry {
  final _storages = <String, InMemoryTokenStorage<String>>{};

  InMemoryTokenStorage<String> call(FreshSession session) {
    return _storages.putIfAbsent(
      session.userId,
      InMemoryTokenStorage<String>.new,
    );
  }

  InMemoryTokenStorage<String> forUserId(String userId) {
    return _storages.putIfAbsent(
      userId,
      InMemoryTokenStorage<String>.new,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FreshSessionController<_TestFresh, String> _createController({
  SessionsStorage? sessionsStorage,
  _TokenStorageRegistry? registry,
}) {
  final storage = sessionsStorage ?? InMemorySessionsStorage();
  final reg = registry ?? _TokenStorageRegistry();
  return FreshSessionController<_TestFresh, String>(
    sessionsStorage: storage,
    tokenStorageBuilder: reg.call,
    freshBuilder: _TestFresh.new,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(SessionsSnapshot.empty);
  });

  // ================================================================
  // FreshSession
  // ================================================================

  group('FreshSession', () {
    final now = DateTime.utc(2025);
    final later = DateTime.utc(2025, 2);

    FreshSession session() => FreshSession(
          userId: 'u1',
          createdAt: now,
          updatedAt: now,
        );

    test('toJson produces expected map', () {
      final json = session().toJson();

      expect(json, <String, Object?>{
        'userId': 'u1',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
    });

    test('fromJson round-trip', () {
      final original = session();
      final restored = FreshSession.fromJson(original.toJson());

      expect(restored, equals(original));
    });

    test('fromJson throws on missing userId', () {
      expect(
        () => FreshSession.fromJson(<String, Object?>{}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws on missing createdAt/updatedAt', () {
      expect(
        () => FreshSession.fromJson(<String, Object?>{
          'userId': 'x',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith replaces fields', () {
      final copy = session().copyWith(updatedAt: later);

      expect(copy.userId, 'u1');
      expect(copy.updatedAt, later);
      expect(copy.createdAt, now);
    });

    test('copyWith with no args returns equivalent copy', () {
      final original = session();
      final copy = original.copyWith();

      expect(copy, equals(original));
      expect(identical(copy, original), isFalse);
    });

    test('== returns true for equal sessions', () {
      expect(session(), equals(session()));
    });

    test('== returns false for different sessions', () {
      final a = session();
      final b = FreshSession(
        userId: 'u2',
        createdAt: now,
        updatedAt: now,
      );

      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with ==', () {
      expect(session().hashCode, equals(session().hashCode));
    });

    test('toString contains userId', () {
      final s = session().toString();

      expect(s, contains('u1'));
      expect(s, startsWith('FreshSession('));
    });
  });

  // ================================================================
  // SessionsSnapshot
  // ================================================================

  group('SessionsSnapshot', () {
    final now = DateTime.utc(2025);

    FreshSession s(String userId) => FreshSession(
          userId: userId,
          createdAt: now,
          updatedAt: now,
        );

    test('empty has no sessions and null active', () {
      expect(SessionsSnapshot.empty.sessions, isEmpty);
      expect(SessionsSnapshot.empty.activeUserId, isNull);
      expect(SessionsSnapshot.empty.isEmpty, isTrue);
    });

    test('activeSession resolves from sessions', () {
      final snap = SessionsSnapshot(
        sessions: [s('a'), s('b')],
        activeUserId: 'b',
      );

      expect(snap.activeSession, equals(s('b')));
    });

    test('activeSession returns null for missing userId', () {
      final snap = SessionsSnapshot(
        sessions: [s('a')],
        activeUserId: 'missing',
      );

      expect(snap.activeSession, isNull);
    });

    test('activeSession returns null when activeUserId is null', () {
      final snap = SessionsSnapshot(sessions: [s('a')]);

      expect(snap.activeSession, isNull);
    });

    test('toJson produces expected map', () {
      final snap = SessionsSnapshot(
        sessions: [s('a')],
        activeUserId: 'a',
      );

      final json = snap.toJson();

      expect(json['activeUserId'], 'a');
      expect(json['sessions'], isA<List<Object?>>());
      expect(
        (json['sessions']! as List).length,
        1,
      );
    });

    test('fromJson round-trip', () {
      final original = SessionsSnapshot(
        sessions: [s('a'), s('b')],
        activeUserId: 'a',
      );
      final restored =
          SessionsSnapshot.fromJson(original.toJson());

      expect(restored, equals(original));
    });

    test('fromJson throws on missing sessions list', () {
      expect(
        () => SessionsSnapshot.fromJson(
          <String, Object?>{'activeUserId': 'a'},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith replaces sessions', () {
      final snap = SessionsSnapshot(sessions: [s('a')]);
      final copy = snap.copyWith(sessions: [s('a'), s('b')]);

      expect(copy.sessions, hasLength(2));
    });

    test('copyWith can set activeUserId to null', () {
      final snap = SessionsSnapshot(
        sessions: [s('a')],
        activeUserId: 'a',
      );
      final copy = snap.copyWith(activeUserId: () => null);

      expect(copy.activeUserId, isNull);
    });

    test('== returns true for equal snapshots', () {
      final a = SessionsSnapshot(
        sessions: [s('x')],
        activeUserId: 'x',
      );
      final b = SessionsSnapshot(
        sessions: [s('x')],
        activeUserId: 'x',
      );

      expect(a, equals(b));
    });

    test('== returns false for different sessions', () {
      final a = SessionsSnapshot(sessions: [s('x')]);
      final b = SessionsSnapshot(sessions: [s('y')]);

      expect(a, isNot(equals(b)));
    });

    test('== returns false for different active userId', () {
      final a = SessionsSnapshot(
        sessions: [s('x')],
        activeUserId: 'x',
      );
      final b = SessionsSnapshot(sessions: [s('x')]);

      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with ==', () {
      final a = SessionsSnapshot(
        sessions: [s('x')],
        activeUserId: 'x',
      );
      final b = SessionsSnapshot(
        sessions: [s('x')],
        activeUserId: 'x',
      );

      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString contains session count', () {
      final snap = SessionsSnapshot(sessions: [s('a'), s('b')]);

      expect(snap.toString(), contains('2'));
      expect(
        snap.toString(),
        startsWith('SessionsSnapshot('),
      );
    });
  });

  // ================================================================
  // InMemorySessionsStorage
  // ================================================================

  group('InMemorySessionsStorage', () {
    test('read returns empty by default', () async {
      final storage = InMemorySessionsStorage();

      expect(await storage.read(), SessionsSnapshot.empty);
    });

    test('write and read round-trip', () async {
      final storage = InMemorySessionsStorage();
      final now = DateTime.utc(2025);
      final snap = SessionsSnapshot(
        sessions: [
          FreshSession(
            userId: 'u1',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        activeUserId: 'u1',
      );

      await storage.write(snap);

      expect(await storage.read(), equals(snap));
    });

    test('clear resets to empty', () async {
      final storage = InMemorySessionsStorage();
      final now = DateTime.utc(2025);
      await storage.write(
        SessionsSnapshot(
          sessions: [
            FreshSession(
              userId: 'u1',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );

      await storage.clear();

      expect(await storage.read(), SessionsSnapshot.empty);
    });
  });

  // ================================================================
  // FreshSessionController
  // ================================================================

  group('FreshSessionController', () {
    // ------ hydration ------

    test('ready hydrates snapshot and active session', () async {
      final storage = InMemorySessionsStorage();
      final now = DateTime.now();
      final record = FreshSession(
        userId: 'u1',
        createdAt: now,
        updatedAt: now,
      );
      await storage.write(
        SessionsSnapshot(
          sessions: [record],
          activeUserId: 'u1',
        ),
      );

      final tokenReg = _TokenStorageRegistry();
      await tokenReg.forUserId('u1').write('tok_u1');

      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: storage,
        tokenStorageBuilder: tokenReg.call,
        freshBuilder: _TestFresh.new,
      );
      await ctrl.ready;

      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(ctrl.activeSession, equals(record));
      expect(ctrl.fresh, isNotNull);

      await ctrl.close();
    });

    test('ready with empty storage produces null active and fresh', () async {
      final ctrl = _createController();
      await ctrl.ready;

      expect(ctrl.snapshot.isEmpty, isTrue);
      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);

      await ctrl.close();
    });

    // ------ saveSession ------

    test('saveSession with makeActive builds fresh', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = _createController(registry: reg);
      await ctrl.ready;

      final record = await ctrl.saveSession(
        token: 'my_token',
        userId: 'u1',
      );

      expect(record.userId, 'u1');
      expect(ctrl.activeSession, equals(record));
      expect(ctrl.fresh, isNotNull);

      final storedToken = await reg.forUserId('u1').read();
      expect(storedToken, 'my_token');

      await ctrl.close();
    });

    test('saveSession with makeActive: false keeps previous state', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      final firstFresh = ctrl.fresh;

      await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );

      expect(ctrl.snapshot.sessions, hasLength(2));
      expect(ctrl.activeSession!.userId, 'u1');
      expect(
        identical(ctrl.fresh, firstFresh),
        isTrue,
        reason: 'fresh should not be rebuilt when makeActive is false',
      );

      await ctrl.close();
    });

    test('saveSession for existing userId updates record', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final first = await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      final second = await ctrl.saveSession(
        token: 'tok1_new',
        userId: 'u1',
      );

      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(second.createdAt, first.createdAt);
      expect(
        second.updatedAt.isAfter(first.updatedAt) ||
            second.updatedAt == first.updatedAt,
        isTrue,
      );

      await ctrl.close();
    });

    // ------ setActiveSession ------

    test('setActiveSession rebuilds fresh instance', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      final freshForS1 = ctrl.fresh;

      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );

      await ctrl.setActiveSession(s2);

      expect(ctrl.activeSession, equals(s2));
      expect(identical(ctrl.fresh, freshForS1), isFalse);
      expect(ctrl.fresh, isNotNull);

      await ctrl.close();
    });

    test('setActiveSession throws for unknown session', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final unknown = FreshSession(
        userId: 'x',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => ctrl.setActiveSession(unknown),
        throwsA(isA<StateError>()),
      );

      await ctrl.close();
    });

    // ------ removeSession ------

    test('removeSession active clears fresh', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = _createController(registry: reg);
      await ctrl.ready;

      final s1 = await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );

      await ctrl.removeSession(s1);

      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);
      expect(ctrl.snapshot.isEmpty, isTrue);

      final storedToken = await reg.forUserId('u1').read();
      expect(storedToken, isNull);

      await ctrl.close();
    });

    test('removeSession inactive does not touch fresh', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );

      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );

      await ctrl.removeSession(s2);

      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(ctrl.fresh, isNotNull);

      await ctrl.close();
    });

    // ------ clearAllSessions ------

    test('clearAllSessions removes all metadata and tokens', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = _createController(registry: reg);
      await ctrl.ready;

      await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );

      await ctrl.clearAllSessions();

      expect(ctrl.snapshot.isEmpty, isTrue);
      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);

      expect(await reg.forUserId('u1').read(), isNull);
      expect(await reg.forUserId('u2').read(), isNull);

      await ctrl.close();
    });

    // ------ streams ------

    test('freshStream does not reuse instance between sessions', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final freshInstances = <_TestFresh?>[];
      final sub = ctrl.freshStream.listen(freshInstances.add);

      final s1 = await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );

      await ctrl.setActiveSession(s2);
      await ctrl.setActiveSession(s1);

      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await ctrl.close();

      final nonNullInstances = freshInstances.where((f) => f != null).toSet();
      expect(
        nonNullInstances.length,
        greaterThanOrEqualTo(3),
        reason: 'each switch should produce a new instance',
      );
    });

    test('snapshotStream emits on mutations', () async {
      final snapshots = <SessionsSnapshot>[];

      final ctrl = _createController();
      final sub = ctrl.snapshotStream.listen(snapshots.add);

      await ctrl.ready;

      await ctrl.saveSession(
        token: 'tok',
        userId: 'u1',
      );
      await ctrl.removeSession(ctrl.snapshot.sessions.first);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await ctrl.close();

      expect(snapshots.length, greaterThanOrEqualTo(3));
    });

    test('activeSessionStream emits on session switch', () async {
      final activeSessions = <FreshSession?>[];

      final ctrl = _createController();
      final sub = ctrl.activeSessionStream.listen(activeSessions.add);

      await ctrl.ready;

      final s1 = await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );
      await ctrl.setActiveSession(s2);

      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await ctrl.close();

      // null (hydration) -> s1 (save) -> s2 (switch)
      expect(activeSessions, hasLength(3));
      expect(activeSessions[0], isNull);
      expect(activeSessions[1]?.userId, s1.userId);
      expect(activeSessions[2]?.userId, s2.userId);
    });

    test('activeSessionChangedStream skips nulls', () async {
      final changed = <FreshSession>[];

      final ctrl = _createController();
      final sub =
          ctrl.activeSessionChangedStream.listen(changed.add);

      await ctrl.ready;

      final s1 = await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
      );
      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );
      await ctrl.setActiveSession(s2);
      await ctrl.removeSession(s2);

      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await ctrl.close();

      // s1 (save) -> s2 (switch), no null after remove
      expect(changed, hasLength(2));
      expect(changed[0].userId, s1.userId);
      expect(changed[1].userId, s2.userId);
    });

    // ------ close ------

    test('operations throw after close', () async {
      final ctrl = _createController();
      await ctrl.ready;
      await ctrl.close();

      expect(
        () => ctrl.saveSession(
          token: 'tok',
          userId: 'u1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    // ------ sessionsStorage interaction ------

    test('persists snapshot to storage on every mutation', () async {
      final storage = _MockSessionsStorage();
      when(storage.read).thenAnswer((_) async => SessionsSnapshot.empty);
      when(() => storage.write(any())).thenAnswer((_) async {});

      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: storage,
        tokenStorageBuilder: _TokenStorageRegistry().call,
        freshBuilder: _TestFresh.new,
      );
      await ctrl.ready;

      await ctrl.saveSession(
        token: 'tok',
        userId: 'u1',
      );

      verify(() => storage.write(any())).called(greaterThanOrEqualTo(1));

      await ctrl.close();
    });
  });
}
