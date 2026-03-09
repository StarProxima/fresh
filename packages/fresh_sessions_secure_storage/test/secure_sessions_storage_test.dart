import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_sessions/fresh_sessions.dart';
import 'package:fresh_sessions_secure_storage/fresh_sessions_secure_storage.dart';

// -----------------------------------------------------------
// Test doubles
// -----------------------------------------------------------

class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  final List<String> deletedKeys = <String>[];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletedKeys.add(key);
    values.remove(key);
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      deletedKeys.add(key);
      values.remove(key);
      return;
    }
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

// -----------------------------------------------------------
// Helpers
// -----------------------------------------------------------

FreshSession _session({
  required String userId,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.utc(2025);
  return FreshSession(
    userId: userId,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  late FakeFlutterSecureStorage fakeStorage;
  late List<Object> corruptionErrors;

  setUp(() {
    fakeStorage = FakeFlutterSecureStorage();
    corruptionErrors = <Object>[];
  });

  SecureSessionsStorage createStorage({
    String storageKey = SecureSessionsStorage.defaultStorageKey,
  }) {
    return SecureSessionsStorage(
      storage: fakeStorage,
      storageKey: storageKey,
      onCorruptedSessions: (error, stackTrace) {
        corruptionErrors.add(error);
      },
    );
  }

  group('SecureSessionsStorage', () {
    test('read returns empty snapshot when nothing stored', () async {
      final storage = createStorage();

      final snapshot = await storage.read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors, isEmpty);
    });

    test('write and read round-trip', () async {
      final storage = createStorage();
      final session = _session(userId: 'u1');
      final snapshot = SessionsSnapshot(
        sessions: [session],
        activeUserId: 'u1',
      );

      await storage.write(snapshot);
      final restored = await storage.read();

      expect(restored.sessions, hasLength(1));
      expect(restored.activeUserId, 'u1');
      expect(restored.sessions.first.userId, 'u1');
      expect(
        restored.sessions.first.createdAt,
        session.createdAt,
      );
      expect(
        restored.sessions.first.updatedAt,
        session.updatedAt,
      );
    });

    test('round-trip with multiple sessions', () async {
      final storage = createStorage();
      final snapshot = SessionsSnapshot(
        sessions: [
          _session(userId: 'u1'),
          _session(userId: 'u2'),
          _session(userId: 'u3'),
        ],
        activeUserId: 'u2',
      );

      await storage.write(snapshot);
      final restored = await storage.read();

      expect(restored.sessions, hasLength(3));
      expect(restored.activeUserId, 'u2');
    });

    test('round-trip with null activeUserId', () async {
      final storage = createStorage();
      final snapshot = SessionsSnapshot(
        sessions: [_session(userId: 'u1')],
      );

      await storage.write(snapshot);
      final restored = await storage.read();

      expect(restored.activeUserId, isNull);
      expect(restored.sessions, hasLength(1));
    });

    test('clear removes data', () async {
      final storage = createStorage();
      await storage.write(
        SessionsSnapshot(
          sessions: [_session(userId: 'u1')],
        ),
      );

      await storage.clear();
      final restored = await storage.read();

      expect(restored, SessionsSnapshot.empty);
      expect(fakeStorage.deletedKeys, contains('fresh_sessions'));
    });

    test('custom storageKey is used', () async {
      final storage = createStorage(storageKey: 'my_sessions');
      await storage.write(
        SessionsSnapshot(
          sessions: [_session(userId: 'u1')],
        ),
      );

      expect(fakeStorage.values.containsKey('my_sessions'), isTrue);
      expect(
        fakeStorage.values.containsKey('fresh_sessions'),
        isFalse,
      );
    });

    test('writes versioned envelope', () async {
      final storage = createStorage();
      await storage.write(
        SessionsSnapshot(
          sessions: [_session(userId: 'u1')],
          activeUserId: 'u1',
        ),
      );

      final raw = fakeStorage.values['fresh_sessions']!;
      final envelope =
          jsonDecode(raw) as Map<String, Object?>;

      expect(envelope['schemaVersion'], 1);
      expect(envelope['payload'], isA<Map<String, Object?>>());

      final payload =
          envelope['payload']! as Map<String, Object?>;
      expect(payload['activeUserId'], 'u1');
      expect(payload['sessions'], isA<List<Object?>>());
    });

    // ---- Corrupted data handling ----

    test('returns empty and reports on invalid JSON', () async {
      fakeStorage.values['fresh_sessions'] = 'not-json';

      final storage = createStorage();
      final snapshot = await storage.read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(fakeStorage.values.containsKey('fresh_sessions'), isFalse);
      expect(corruptionErrors, hasLength(1));
    });

    test('returns empty when envelope is not a map', () async {
      fakeStorage.values['fresh_sessions'] =
          jsonEncode(<Object?>['list']);

      final snapshot = await createStorage().read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('returns empty when schemaVersion missing', () async {
      fakeStorage.values['fresh_sessions'] = jsonEncode(
        <String, Object?>{
          'payload': <String, Object?>{
            'sessions': <Object?>[],
          },
        },
      );

      final snapshot = await createStorage().read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('returns empty when schemaVersion is newer', () async {
      fakeStorage.values['fresh_sessions'] = jsonEncode(
        <String, Object?>{
          'schemaVersion': 999,
          'payload': <String, Object?>{
            'sessions': <Object?>[],
          },
        },
      );

      final snapshot = await createStorage().read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('returns empty when payload is not a map', () async {
      fakeStorage.values['fresh_sessions'] = jsonEncode(
        <String, Object?>{
          'schemaVersion': 1,
          'payload': 'not-a-map',
        },
      );

      final snapshot = await createStorage().read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('returns empty when sessions list is missing', () async {
      fakeStorage.values['fresh_sessions'] = jsonEncode(
        <String, Object?>{
          'schemaVersion': 1,
          'payload': <String, Object?>{
            'activeUserId': 'x',
          },
        },
      );

      final snapshot = await createStorage().read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('returns empty when a session entry is malformed', () async {
      fakeStorage.values['fresh_sessions'] = jsonEncode(
        <String, Object?>{
          'schemaVersion': 1,
          'payload': <String, Object?>{
            'sessions': [
              <String, Object?>{'userId': 123},
            ],
          },
        },
      );

      final snapshot = await createStorage().read();

      expect(snapshot, SessionsSnapshot.empty);
      expect(corruptionErrors, hasLength(1));
    });

    test('no handler is fine - still returns empty on corruption',
        () async {
      fakeStorage.values['fresh_sessions'] = 'broken';

      final storage = SecureSessionsStorage(
        storage: fakeStorage,
      );
      final snapshot = await storage.read();

      expect(snapshot, SessionsSnapshot.empty);
    });
  });
}
