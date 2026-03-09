import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_secure_storage/fresh_secure_storage.dart';

class TestToken extends Token {
  const TestToken({
    required super.accessToken,
    required this.userId,
    required this.environment,
    super.refreshToken,
    super.tokenType = 'bearer',
    this.expiresAtValue,
  });

  final String userId;
  final String environment;
  final DateTime? expiresAtValue;

  @override
  DateTime? get expiresAt => expiresAtValue;
}

class TestTokenCodec implements TokenCodec<TestToken> {
  @override
  Map<String, Object?> encode(TestToken token) {
    return <String, Object?>{
      'accessToken': token.accessToken,
      'refreshToken': token.refreshToken,
      'tokenType': token.tokenType,
      'userId': token.userId,
      'environment': token.environment,
    };
  }

  @override
  TestToken decode(Map<String, Object?> json) {
    return TestToken(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken'] as String?,
      tokenType: json['tokenType'] as String? ?? 'bearer',
      userId: json['userId']! as String,
      environment: json['environment']! as String,
    );
  }
}

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

class StaticMigration implements StorageMigration {
  const StaticMigration({
    required this.fromVersion,
    required this.toVersion,
    required this.environment,
  });

  @override
  final int fromVersion;

  @override
  final int toVersion;

  final String environment;

  @override
  Map<String, Object?> migrate(Map<String, Object?> payload) {
    return <String, Object?>{
      ...payload,
      'environment': environment,
    };
  }
}

class StaticLegacyTokenReader<T> implements LegacyTokenReader<T> {
  const StaticLegacyTokenReader(this.result);

  final LegacyReadResult<T>? result;

  @override
  Future<LegacyReadResult<T>?> read() async {
    return result;
  }
}

class ThrowingLegacyTokenReader<T> implements LegacyTokenReader<T> {
  const ThrowingLegacyTokenReader(this.error);

  final Object error;

  @override
  Future<LegacyReadResult<T>?> read() {
    // ignore: only_throw_errors
    throw error;
  }
}

void main() {
  group('OAuth2TokenCodec', () {
    const codec = OAuth2TokenCodec();

    test('encode/decode round-trip', () {
      final issuedAt = DateTime.utc(2024, 1, 2, 3, 4, 5);
      final token = OAuth2Token(
        accessToken: 'access',
        refreshToken: 'refresh',
        tokenType: 'bearer',
        expiresIn: 3600,
        scope: 'profile',
        issuedAt: issuedAt,
      );

      final json = codec.encode(token);
      expect(json, <String, Object?>{
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'tokenType': 'bearer',
        'expiresIn': 3600,
        'scope': 'profile',
        'issuedAt': issuedAt.toIso8601String(),
      });

      final decoded = codec.decode(json);
      expect(decoded.accessToken, 'access');
      expect(decoded.refreshToken, 'refresh');
      expect(decoded.tokenType, 'bearer');
      expect(decoded.expiresIn, 3600);
      expect(decoded.scope, 'profile');
      expect(decoded.issuedAt, issuedAt);
    });
  });

  group('JsonLegacyTokenReader', () {
    late FakeFlutterSecureStorage storage;
    late TestTokenCodec codec;

    setUp(() {
      storage = FakeFlutterSecureStorage();
      codec = TestTokenCodec();
    });

    test('returns null when no legacy payload exists', () async {
      final reader = JsonLegacyTokenReader<TestToken>(
        read: () => storage.read(key: 'token'),
        codec: codec,
      );

      expect(await reader.read(), isNull);
    });

    test('reads and cleans up a legacy payload', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'tokenType': 'bearer',
        'userId': 'user-1',
        'environment': 'prod',
      });

      final reader = JsonLegacyTokenReader<TestToken>(
        read: () => storage.read(key: 'token'),
        codec: codec,
        cleanup: () => storage.delete(key: 'token'),
      );
      final result = await reader.read();

      expect(result, isNotNull);
      expect(result!.token.userId, 'user-1');
      await result.runCleanup();
      expect(storage.deletedKeys, <String>['token']);
    });

    test('throws when the legacy payload is not a json object', () {
      storage.values['token'] = jsonEncode(<Object?>['not', 'a', 'map']);
      final reader = JsonLegacyTokenReader<TestToken>(
        read: () => storage.read(key: 'token'),
        codec: codec,
      );

      expect(reader.read, throwsA(isA<FormatException>()));
    });
  });

  group('SecureTokenStorage', () {
    late FakeFlutterSecureStorage storage;
    late TestTokenCodec codec;
    late List<Object> corruptionErrors;

    setUp(() {
      storage = FakeFlutterSecureStorage();
      codec = TestTokenCodec();
      corruptionErrors = <Object>[];
    });

    SecureTokenStorage<TestToken> createStorage({
      int schemaVersion = SecureTokenStorage.defaultSchemaVersion,
      List<StorageMigration> migrations = const <StorageMigration>[],
      List<LegacyTokenReader<TestToken>> legacyReaders =
          const <LegacyTokenReader<TestToken>>[],
    }) {
      return SecureTokenStorage<TestToken>(
        storage: storage,
        codec: codec,
        storageKey: 'token',
        schemaVersion: schemaVersion,
        migrations: migrations,
        legacyReaders: legacyReaders,
        onCorruptedToken: (error, stackTrace) async {
          corruptionErrors.add(error);
          expect(stackTrace, isA<StackTrace>());
        },
      );
    }

    test('writes and reads a token', () async {
      final tokenStorage = createStorage();
      const token = TestToken(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'user-1',
        environment: 'prod',
      );

      await tokenStorage.write(token);

      final envelope =
          jsonDecode(storage.values['token']!) as Map<String, Object?>;
      expect(envelope['schemaVersion'], 1);

      final restored = await tokenStorage.read();
      expect(restored!.accessToken, 'access');
      expect(restored.userId, 'user-1');
    });

    test('deletes the active key', () async {
      final tokenStorage = createStorage();
      storage.values['token'] = 'value';

      await tokenStorage.delete();

      expect(storage.values, isEmpty);
      expect(storage.deletedKeys, <String>['token']);
    });

    test('returns null when nothing is stored', () async {
      expect(await createStorage().read(), isNull);
      expect(corruptionErrors, isEmpty);
    });

    test('migrates an older envelope and rewrites it', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'payload': <String, Object?>{
          'accessToken': 'access',
          'refreshToken': 'refresh',
          'tokenType': 'bearer',
          'userId': 'user-1',
        },
      });

      final tokenStorage = createStorage(
        schemaVersion: 2,
        migrations: const <StorageMigration>[
          StaticMigration(
            fromVersion: 1,
            toVersion: 2,
            environment: 'prod',
          ),
        ],
      );

      final token = await tokenStorage.read();
      expect(token!.environment, 'prod');

      final rewritten =
          jsonDecode(storage.values['token']!) as Map<String, Object?>;
      expect(rewritten['schemaVersion'], 2);
    });

    test('skips null-returning reader and recovers from next', () async {
      final tokenStorage = createStorage(
        legacyReaders: <LegacyTokenReader<TestToken>>[
          const StaticLegacyTokenReader<TestToken>(null),
          StaticLegacyTokenReader<TestToken>(
            LegacyReadResult<TestToken>(
              token: const TestToken(
                accessToken: 'access',
                refreshToken: 'refresh',
                userId: 'user-1',
                environment: 'stage',
              ),
              cleanup: () => storage.delete(key: 'legacy-token'),
            ),
          ),
        ],
      );
      storage.values['legacy-token'] = 'stale';

      final token = await tokenStorage.read();

      expect(token!.environment, 'stage');
      expect(storage.values.containsKey('token'), isTrue);
      expect(storage.deletedKeys, <String>['legacy-token']);
    });

    test('falls back to legacy readers on corrupted payload', () async {
      storage.values['token'] = 'not-json';
      storage.values['legacy-token'] = jsonEncode(<String, Object?>{
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'tokenType': 'bearer',
        'userId': 'user-1',
        'environment': 'prod',
      });

      final tokenStorage = createStorage(
        legacyReaders: <LegacyTokenReader<TestToken>>[
          JsonLegacyTokenReader<TestToken>(
            read: () => storage.read(key: 'legacy-token'),
            codec: codec,
            cleanup: () => storage.delete(key: 'legacy-token'),
          ),
        ],
      );

      final token = await tokenStorage.read();

      expect(token!.userId, 'user-1');
      expect(storage.deletedKeys, <String>['legacy-token']);
    });

    test('continues to next legacy reader after an error', () async {
      final tokenStorage = createStorage(
        legacyReaders: const <LegacyTokenReader<TestToken>>[
          ThrowingLegacyTokenReader<TestToken>(
            FormatException('broken legacy'),
          ),
          StaticLegacyTokenReader<TestToken>(
            LegacyReadResult<TestToken>(
              token: TestToken(
                accessToken: 'access',
                refreshToken: 'refresh',
                userId: 'user-1',
                environment: 'prod',
              ),
            ),
          ),
        ],
      );

      final token = await tokenStorage.read();

      expect(token, isNotNull);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    // Corruption: each test hits a unique throw statement

    test('reports corruption when payload is not a map', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'payload': <Object?>['broken'],
      });

      expect(await createStorage().read(), isNull);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('reports corruption when schemaVersion is not an int', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'schemaVersion': '1',
        'payload': <String, Object?>{},
      });

      expect(await createStorage().read(), isNull);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('reports corruption when schemaVersion is zero', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'schemaVersion': 0,
        'payload': <String, Object?>{},
      });

      expect(await createStorage().read(), isNull);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('reports corruption when schemaVersion is newer', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'payload': <String, Object?>{
          'accessToken': 'a',
          'refreshToken': 'r',
          'tokenType': 'bearer',
          'userId': 'u',
          'environment': 'e',
        },
      });

      expect(await createStorage().read(), isNull);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    test('reports corruption when required migration is missing', () async {
      storage.values['token'] = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'payload': <String, Object?>{
          'accessToken': 'a',
          'refreshToken': 'r',
          'tokenType': 'bearer',
          'userId': 'u',
          'environment': 'e',
        },
      });

      expect(await createStorage(schemaVersion: 2).read(), isNull);
      expect(corruptionErrors.single, isA<StateError>());
    });

    test('reports corruption when envelope is not a json object', () async {
      storage.values['token'] = jsonEncode(<Object?>['broken']);

      expect(await createStorage().read(), isNull);
      expect(corruptionErrors.single, isA<FormatException>());
    });

    // Validation

    test('throws for invalid migration source versions', () {
      expect(
        () => createStorage(
          migrations: const <StorageMigration>[
            StaticMigration(fromVersion: 0, toVersion: 1, environment: 'e'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('throws for invalid migration target versions', () {
      expect(
        () => createStorage(
          migrations: const <StorageMigration>[
            StaticMigration(fromVersion: 1, toVersion: 1, environment: 'e'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('throws for duplicate migration source versions', () {
      expect(
        () => createStorage(
          schemaVersion: 3,
          migrations: const <StorageMigration>[
            StaticMigration(fromVersion: 1, toVersion: 2, environment: 'a'),
            StaticMigration(fromVersion: 1, toVersion: 3, environment: 'b'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
