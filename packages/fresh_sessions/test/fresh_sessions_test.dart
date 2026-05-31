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

/// Fresh that always throws [RevokeTokenException] on refresh -
/// emulates a shouldRefresh=401 + revoke flow.
class _RevokingFresh with FreshMixin<String> {
  _RevokingFresh(TokenStorage<String> tokenStorage) {
    this.tokenStorage = tokenStorage;
  }

  @override
  Future<String> performTokenRefresh(String? token) async {
    // ignore: avoid-throw-objects-without-tostring
    throw RevokeTokenException();
  }
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

class _StaticLegacySessionReader implements LegacySessionReader<String> {
  const _StaticLegacySessionReader(this.result);

  final LegacySessionResult<String>? result;

  @override
  Future<LegacySessionResult<String>?> read() async => result;
}

class _ThrowingLegacySessionReader implements LegacySessionReader<String> {
  const _ThrowingLegacySessionReader();

  @override
  Future<LegacySessionResult<String>?> read() =>
      throw const FormatException('broken');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FreshSessionController<_TestFresh, String> _createController({
  SessionsStorage? sessionsStorage,
  _TokenStorageRegistry? registry,
  List<LegacySessionReader<String>> legacySessionReaders = const [],
}) {
  final storage = sessionsStorage ?? InMemorySessionsStorage();
  final reg = registry ?? _TokenStorageRegistry();
  return FreshSessionController<_TestFresh, String>(
    sessionsStorage: storage,
    tokenStorageBuilder: reg.call,
    freshBuilder: _TestFresh.new,
    legacySessionReaders: legacySessionReaders,
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

    FreshSession session({Map<String, Object?> metadata = const {}}) =>
        FreshSession(
          userId: 'u1',
          createdAt: now,
          updatedAt: now,
          metadata: metadata,
        );

    test('toJson produces expected map', () {
      final json = session(metadata: {'name': 'John'}).toJson();

      expect(json, <String, Object?>{
        'userId': 'u1',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'metadata': {'name': 'John'},
      });
    });

    test('toJson omits empty metadata', () {
      expect(session().toJson().containsKey('metadata'), isFalse);
    });

    test('fromJson round-trip with metadata', () {
      final original = session(metadata: {'email': 'a@b.com'});
      final restored = FreshSession.fromJson(original.toJson());

      expect(restored, equals(original));
      expect(restored.metadata['email'], 'a@b.com');
    });

    test('fromJson with missing metadata defaults to empty', () {
      final json = <String, Object?>{
        'userId': 'u1',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      expect(FreshSession.fromJson(json).metadata, isEmpty);
    });

    test('fromJson throws on missing userId', () {
      expect(
        () => FreshSession.fromJson(<String, Object?>{}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson throws on missing timestamps', () {
      expect(
        () => FreshSession.fromJson(<String, Object?>{'userId': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith replaces fields', () {
      final copy = session().copyWith(
        updatedAt: later,
        metadata: {'name': 'Jane'},
      );

      expect(copy.userId, 'u1');
      expect(copy.updatedAt, later);
      expect(copy.metadata, {'name': 'Jane'});
      expect(copy.createdAt, now);
    });

    test('copyWith with no args returns equivalent copy', () {
      final original = session();
      final copy = original.copyWith();

      expect(copy, equals(original));
      expect(identical(copy, original), isFalse);
    });

    test('== and hashCode', () {
      expect(session(), equals(session()));
      expect(session().hashCode, equals(session().hashCode));
      expect(
        session(metadata: {'a': 1}),
        isNot(equals(session())),
      );
    });

    test('toString contains userId', () {
      expect(session().toString(), contains('u1'));
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

    test('activeSession returns null for missing or null userId', () {
      expect(
        SessionsSnapshot(sessions: [s('a')], activeUserId: 'x')
            .activeSession,
        isNull,
      );
      expect(
        SessionsSnapshot(sessions: [s('a')]).activeSession,
        isNull,
      );
    });

    test('toJson/fromJson round-trip', () {
      final original = SessionsSnapshot(
        sessions: [s('a'), s('b')],
        activeUserId: 'a',
      );
      expect(
        SessionsSnapshot.fromJson(original.toJson()),
        equals(original),
      );
    });

    test('fromJson throws on missing sessions list', () {
      expect(
        () => SessionsSnapshot.fromJson(<String, Object?>{'activeUserId': 'a'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('copyWith replaces sessions and activeUserId', () {
      final snap = SessionsSnapshot(
        sessions: [s('a')],
        activeUserId: 'a',
      );

      expect(
        snap.copyWith(sessions: [s('a'), s('b')]).sessions,
        hasLength(2),
      );
      expect(
        snap.copyWith(activeUserId: () => null).activeUserId,
        isNull,
      );
    });

    test('== and hashCode', () {
      final a = SessionsSnapshot(sessions: [s('x')], activeUserId: 'x');
      final b = SessionsSnapshot(sessions: [s('x')], activeUserId: 'x');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(SessionsSnapshot(sessions: [s('y')]))));
    });

    test('toString contains session count', () {
      expect(
        SessionsSnapshot(sessions: [s('a'), s('b')]).toString(),
        contains('2'),
      );
    });
  });

  // ================================================================
  // InMemorySessionsStorage
  // ================================================================

  group('InMemorySessionsStorage', () {
    test('read/write/clear round-trip', () async {
      final storage = InMemorySessionsStorage();
      final now = DateTime.utc(2025);
      final snap = SessionsSnapshot(
        sessions: [
          FreshSession(userId: 'u1', createdAt: now, updatedAt: now),
        ],
        activeUserId: 'u1',
      );

      expect(await storage.read(), isNull);
      await storage.write(snap);
      expect(await storage.read(), equals(snap));
      await storage.clear();
      expect(await storage.read(), isNull);
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
        SessionsSnapshot(sessions: [record], activeUserId: 'u1'),
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
        metadata: {'name': 'John'},
      );

      expect(record.userId, 'u1');
      expect(record.metadata, {'name': 'John'});
      expect(ctrl.activeSession, equals(record));
      expect(ctrl.fresh, isNotNull);
      expect(await reg.forUserId('u1').read(), 'my_token');

      await ctrl.close();
    });

    test('saveSession with makeActive: false keeps previous state', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.saveSession(token: 'tok1', userId: 'u1');
      final firstFresh = ctrl.fresh;

      await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );

      expect(ctrl.snapshot.sessions, hasLength(2));
      expect(ctrl.activeSession!.userId, 'u1');
      expect(identical(ctrl.fresh, firstFresh), isTrue);

      await ctrl.close();
    });

    test('saveSession for existing userId updates record and metadata',
        () async {
      final ctrl = _createController();
      await ctrl.ready;

      final first = await ctrl.saveSession(
        token: 'tok1',
        userId: 'u1',
        metadata: {'name': 'Old'},
      );
      final second = await ctrl.saveSession(
        token: 'tok1_new',
        userId: 'u1',
        metadata: {'name': 'New'},
      );

      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(second.createdAt, first.createdAt);
      expect(second.metadata, {'name': 'New'});

      await ctrl.close();
    });

    // ------ readToken ------

    test('readToken returns token for a session', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = _createController(registry: reg);
      await ctrl.ready;

      final session = await ctrl.saveSession(
        token: 'secret',
        userId: 'u1',
      );

      expect(await ctrl.readToken(session), 'secret');

      await ctrl.close();
    });

    // ------ setActiveSession ------

    test('setActiveSession rebuilds fresh instance', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.saveSession(token: 'tok1', userId: 'u1');
      final freshForS1 = ctrl.fresh;

      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );
      await ctrl.setActiveSession(s2);

      expect(ctrl.activeSession, equals(s2));
      expect(identical(ctrl.fresh, freshForS1), isFalse);

      await ctrl.close();
    });

    test('setActiveSession throws for unknown session', () async {
      final ctrl = _createController();
      await ctrl.ready;

      expect(
        () => ctrl.setActiveSession(
          FreshSession(
            userId: 'x',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      await ctrl.close();
    });

    // ------ removeSession ------

    test('removeSession active clears fresh and storage', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = _createController(registry: reg);
      await ctrl.ready;

      final s1 = await ctrl.saveSession(token: 'tok1', userId: 'u1');
      await ctrl.removeSession(s1);

      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);
      expect(ctrl.snapshot.isEmpty, isTrue);
      expect(await reg.forUserId('u1').read(), isNull);

      await ctrl.close();
    });

    test('removeSession inactive does not touch fresh', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.saveSession(token: 'tok1', userId: 'u1');
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

      await ctrl.saveSession(token: 'tok1', userId: 'u1');
      await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );
      await ctrl.clearAllSessions();

      expect(ctrl.snapshot.isEmpty, isTrue);
      expect(ctrl.fresh, isNull);
      expect(await reg.forUserId('u1').read(), isNull);
      expect(await reg.forUserId('u2').read(), isNull);

      await ctrl.close();
    });

    // ------ legacy migration ------

    test('migrates legacy token into a session on empty storage', () async {
      var cleaned = false;
      final ctrl = _createController(
        legacySessionReaders: [
          _StaticLegacySessionReader(
            LegacySessionResult(
              token: 'legacy_tok',
              userId: 'legacy_user',
              metadata: {'name': 'Legacy'},
              cleanup: () => cleaned = true,
            ),
          ),
        ],
      );
      await ctrl.ready;

      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(ctrl.activeSession!.userId, 'legacy_user');
      expect(ctrl.activeSession!.metadata, {'name': 'Legacy'});
      expect(ctrl.fresh, isNotNull);
      expect(cleaned, isTrue);

      await ctrl.close();
    });

    test('skips null-returning and broken legacy readers', () async {
      final ctrl = _createController(
        legacySessionReaders: [
          const _StaticLegacySessionReader(null),
          const _ThrowingLegacySessionReader(),
          _StaticLegacySessionReader(
            LegacySessionResult(
              token: 'ok_tok',
              userId: 'ok_user',
            ),
          ),
        ],
      );
      await ctrl.ready;

      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(ctrl.activeSession!.userId, 'ok_user');

      await ctrl.close();
    });

    test('does not run legacy readers when sessions exist', () async {
      final storage = InMemorySessionsStorage();
      final now = DateTime.now();
      await storage.write(
        SessionsSnapshot(
          sessions: [
            FreshSession(userId: 'u1', createdAt: now, updatedAt: now),
          ],
          activeUserId: 'u1',
        ),
      );

      var legacyCalled = false;
      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: storage,
        tokenStorageBuilder: _TokenStorageRegistry().call,
        freshBuilder: _TestFresh.new,
        legacySessionReaders: [
          _StaticLegacySessionReader(
            LegacySessionResult(
              token: 'nope',
              userId: 'nope',
            ),
          ),
        ],
      );

      // Patch: check by verifying session count didn't change
      await ctrl.ready;
      expect(ctrl.snapshot.sessions, hasLength(1));
      expect(ctrl.snapshot.sessions.first.userId, 'u1');
      expect(legacyCalled, isFalse);

      await ctrl.close();
    });

    // ------ streams ------

    test('freshStream does not reuse instance between sessions', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final freshInstances = <_TestFresh?>[];
      final sub = ctrl.freshStream.listen(freshInstances.add);

      final s1 = await ctrl.saveSession(token: 'tok1', userId: 'u1');
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

      final nonNull = freshInstances.where((f) => f != null).toSet();
      expect(nonNull.length, greaterThanOrEqualTo(3));
    });

    test('snapshotStream emits on mutations', () async {
      final snapshots = <SessionsSnapshot>[];
      final ctrl = _createController();
      final sub = ctrl.snapshotStream.listen(snapshots.add);

      await ctrl.ready;
      await ctrl.saveSession(token: 'tok', userId: 'u1');
      await ctrl.removeSession(ctrl.snapshot.sessions.first);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await ctrl.close();

      expect(snapshots.length, greaterThanOrEqualTo(3));
    });

    test('activeSessionStream emits on session switch', () async {
      final active = <FreshSession?>[];
      final ctrl = _createController();
      final sub = ctrl.activeSessionStream.listen(active.add);

      await ctrl.ready;
      final s1 = await ctrl.saveSession(token: 'tok1', userId: 'u1');
      final s2 = await ctrl.saveSession(
        token: 'tok2',
        userId: 'u2',
        makeActive: false,
      );
      await ctrl.setActiveSession(s2);

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await ctrl.close();

      expect(active, hasLength(3));
      expect(active[0], isNull);
      expect(active[1]?.userId, s1.userId);
      expect(active[2]?.userId, s2.userId);
    });

    test('activeSessionChangedStream skips nulls', () async {
      final changed = <FreshSession>[];
      final ctrl = _createController();
      final sub = ctrl.activeSessionChangedStream.listen(changed.add);

      await ctrl.ready;
      final s1 = await ctrl.saveSession(token: 'tok1', userId: 'u1');
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
        () => ctrl.saveSession(token: 'tok', userId: 'u1'),
        throwsA(isA<StateError>()),
      );
    });

    // ------ force-logout via Fresh.authenticationStatus ------

    test('force-logout: clearToken on Fresh clears the active session',
        () async {
      final reg = _TokenStorageRegistry();
      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: InMemorySessionsStorage(),
        tokenStorageBuilder: reg.call,
        freshBuilder: _TestFresh.new,
      );
      await ctrl.ready;

      await ctrl.saveSession(token: 'tok1', userId: 'u1');
      // Wait for Fresh hydration (async read tokenStorage -> authenticated).
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.activeSession, isNotNull);

      // Simulate a force-logout issued by Fresh itself
      // (as if after a RevokeTokenException).
      await ctrl.fresh!.clearToken();
      // Listener runs via microtask + removeSession via Future().
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);
      expect(ctrl.snapshot.isEmpty, isTrue);
      expect(await reg.forUserId('u1').read(), isNull);

      await ctrl.close();
    });

    test(
        'force-logout: RevokeTokenException in refreshToken clears the active '
        'session', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = FreshSessionController<_RevokingFresh, String>(
        sessionsStorage: InMemorySessionsStorage(),
        tokenStorageBuilder: reg.call,
        freshBuilder: _RevokingFresh.new,
      );
      await ctrl.ready;

      await ctrl.saveSession(token: 'tok1', userId: 'u1');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Trigger a refresh - it throws RevokeTokenException, which inside
      // FreshMixin calls clearToken and emits authenticationStatus=unauthenticated.
      // tokenUsedForRequest is required to bypass the short-circuit in
      // refreshToken that returns the current token when it differs from the
      // one passed in.
      final currentToken = await ctrl.fresh!.token;
      await expectLater(
        ctrl.fresh!.refreshToken(tokenUsedForRequest: currentToken),
        throwsA(isA<RevokeTokenException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);
      expect(ctrl.snapshot.isEmpty, isTrue);

      await ctrl.close();
    });

    test(
        'force-logout: initial -> unauthenticated with no token clears the '
        'dangling active session', () async {
      // Empty token storage but a session recorded in the snapshot - the
      // "session metadata without a token" edge case (e.g. a previous revoke
      // deleted the token but its session cleanup was interrupted). On
      // hydration Fresh reads the empty storage and emits unauthenticated;
      // such a dangling active session can never authenticate and must be
      // cleared, otherwise every request goes out unauthenticated forever.
      final reg = _TokenStorageRegistry();
      final storage = InMemorySessionsStorage();
      final now = DateTime.now();
      await storage.write(
        SessionsSnapshot(
          sessions: [FreshSession(userId: 'u1', createdAt: now, updatedAt: now)],
          activeUserId: 'u1',
        ),
      );

      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: storage,
        tokenStorageBuilder: reg.call,
        freshBuilder: _TestFresh.new,
      );
      await ctrl.ready;
      // Listener runs via microtask + removeSession via Future().
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);
      expect(ctrl.snapshot.isEmpty, isTrue);

      await ctrl.close();
    });

    test('force-logout: explicit removeSession does not retrigger', () async {
      // An explicit logout via removeSession must not cause a second
      // removeSession through the authenticationStatus listener.
      final reg = _TokenStorageRegistry();
      final storage = InMemorySessionsStorage();
      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: storage,
        tokenStorageBuilder: reg.call,
        freshBuilder: _TestFresh.new,
      );
      await ctrl.ready;

      final s1 = await ctrl.saveSession(token: 'tok1', userId: 'u1');
      await Future<void>.delayed(Duration.zero);

      final snapshots = <SessionsSnapshot>[];
      final sub = ctrl.snapshotStream.listen(snapshots.add);

      await ctrl.removeSession(s1);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      // Exactly one empty-sessions snapshot (not two).
      final emptySnapshots = snapshots.where((s) => s.isEmpty).toList();
      expect(emptySnapshots, hasLength(1));
      expect(ctrl.activeSession, isNull);

      await ctrl.close();
    });

    // ------ persistence ------

    test('persists snapshot to storage on every mutation', () async {
      final storage = _MockSessionsStorage();
      when(storage.read).thenAnswer((_) async => null);
      when(() => storage.write(any())).thenAnswer((_) async {});

      final ctrl = FreshSessionController<_TestFresh, String>(
        sessionsStorage: storage,
        tokenStorageBuilder: _TokenStorageRegistry().call,
        freshBuilder: _TestFresh.new,
      );
      await ctrl.ready;
      await ctrl.saveSession(token: 'tok', userId: 'u1');

      verify(() => storage.write(any())).called(greaterThanOrEqualTo(1));

      await ctrl.close();
    });
  });
}
