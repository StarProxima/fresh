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

  InMemoryTokenStorage<String> call(String sessionId) {
    return _storages.putIfAbsent(
      sessionId,
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
  SessionIdBuilder? sessionIdBuilder,
}) {
  final storage = sessionsStorage ?? InMemorySessionsStorage();
  final reg = registry ?? _TokenStorageRegistry();
  return FreshSessionController<_TestFresh, String>(
    sessionsStorage: storage,
    tokenStorageBuilder: reg.call,
    freshBuilder: _TestFresh.new,
    sessionIdBuilder: sessionIdBuilder,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(SessionsSnapshot.empty);
  });

  group('FreshSessionController', () {
    // ------ hydration ------

    test('ready hydrates snapshot and active session', () async {
      final storage = InMemorySessionsStorage();
      final now = DateTime.now();
      final record = FreshSession(
        id: 'u1@prod',
        userId: 'u1',
        environment: 'prod',
        createdAt: now,
        updatedAt: now,
      );
      await storage.write(
        SessionsSnapshot(
          sessions: [record],
          activeSessionId: 'u1@prod',
        ),
      );

      final tokenReg = _TokenStorageRegistry();
      await tokenReg('u1@prod').write('tok_u1');

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

    // ------ createSession ------

    test('createSession with makeActive builds fresh', () async {
      final reg = _TokenStorageRegistry();
      final ctrl = _createController(registry: reg);
      await ctrl.ready;

      final record = await ctrl.createSession(
        token: 'my_token',
        userId: 'u1',
        environment: 'prod',
      );

      expect(record.userId, 'u1');
      expect(record.environment, 'prod');
      expect(record.id, 'u1@prod');
      expect(ctrl.activeSession, equals(record));
      expect(ctrl.fresh, isNotNull);

      final storedToken = await reg('u1@prod').read();
      expect(storedToken, 'my_token');

      await ctrl.close();
    });

    test('createSession without environment uses userId as id', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final record = await ctrl.createSession(
        token: 'tok',
        userId: 'u1',
      );

      expect(record.id, 'u1');
      expect(record.environment, isNull);
      expect(ctrl.fresh, isNotNull);

      await ctrl.close();
    });

    test('createSession with makeActive: false keeps previous state', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      final firstFresh = ctrl.fresh;

      await ctrl.createSession(
        token: 'tok2',
        userId: 'u2',
        environment: 'prod',
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

    test('createSession for existing id updates record', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final first = await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      final second = await ctrl.createSession(
        token: 'tok1_new',
        userId: 'u1',
        environment: 'prod',
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

      await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      final freshForS1 = ctrl.fresh;

      final s2 = await ctrl.createSession(
        token: 'tok2',
        userId: 'u2',
        environment: 'prod',
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
        id: 'nope',
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

      final s1 = await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );

      await ctrl.removeSession(s1);

      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);
      expect(ctrl.snapshot.isEmpty, isTrue);

      final storedToken = await reg('u1@prod').read();
      expect(storedToken, isNull);

      await ctrl.close();
    });

    test('removeSession inactive does not touch fresh', () async {
      final ctrl = _createController();
      await ctrl.ready;

      await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );

      final s2 = await ctrl.createSession(
        token: 'tok2',
        userId: 'u2',
        environment: 'prod',
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

      await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      await ctrl.createSession(
        token: 'tok2',
        userId: 'u2',
        environment: 'staging',
        makeActive: false,
      );

      await ctrl.clearAllSessions();

      expect(ctrl.snapshot.isEmpty, isTrue);
      expect(ctrl.activeSession, isNull);
      expect(ctrl.fresh, isNull);

      expect(await reg('u1@prod').read(), isNull);
      expect(await reg('u2@staging').read(), isNull);

      await ctrl.close();
    });

    // ------ sessionIdBuilder ------

    test('custom sessionIdBuilder is used for id generation', () async {
      final ctrl = _createController(
        sessionIdBuilder: (userId, env) => '${env}_$userId',
      );
      await ctrl.ready;

      final record = await ctrl.createSession(
        token: 'tok',
        userId: 'u1',
        environment: 'prod',
      );

      expect(record.id, 'prod_u1');

      await ctrl.close();
    });

    test(
        'default sessionIdBuilder separates same user '
        'in different envs', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final s1 = await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      final s2 = await ctrl.createSession(
        token: 'tok2',
        userId: 'u1',
        environment: 'staging',
        makeActive: false,
      );

      expect(s1.id, isNot(equals(s2.id)));
      expect(ctrl.snapshot.sessions, hasLength(2));

      await ctrl.close();
    });

    // ------ streams ------

    test('freshStream does not reuse instance between sessions', () async {
      final ctrl = _createController();
      await ctrl.ready;

      final freshInstances = <_TestFresh?>[];
      final sub = ctrl.freshStream.listen(freshInstances.add);

      final s1 = await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      final s2 = await ctrl.createSession(
        token: 'tok2',
        userId: 'u2',
        environment: 'prod',
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

      await ctrl.createSession(
        token: 'tok',
        userId: 'u1',
        environment: 'prod',
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

      final s1 = await ctrl.createSession(
        token: 'tok1',
        userId: 'u1',
        environment: 'prod',
      );
      final s2 = await ctrl.createSession(
        token: 'tok2',
        userId: 'u2',
        environment: 'staging',
        makeActive: false,
      );
      await ctrl.setActiveSession(s2);

      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      await ctrl.close();

      // null (hydration) -> s1 (create) -> s2 (switch)
      expect(activeSessions, hasLength(3));
      expect(activeSessions[0], isNull);
      expect(activeSessions[1]?.id, s1.id);
      expect(activeSessions[2]?.id, s2.id);
    });

    // ------ close ------

    test('operations throw after close', () async {
      final ctrl = _createController();
      await ctrl.ready;
      await ctrl.close();

      expect(
        () => ctrl.createSession(
          token: 'tok',
          userId: 'u1',
          environment: 'prod',
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

      await ctrl.createSession(
        token: 'tok',
        userId: 'u1',
        environment: 'prod',
      );

      verify(() => storage.write(any())).called(greaterThanOrEqualTo(1));

      await ctrl.close();
    });
  });
}
