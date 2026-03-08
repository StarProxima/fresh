import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh/fresh.dart';
import 'package:fresh_secure_storage/src/legacy_token_reader.dart';
import 'package:fresh_secure_storage/src/storage_migration.dart';
import 'package:fresh_secure_storage/src/token_codec.dart';

/// Callback invoked after a corrupted token payload is discarded.
typedef CorruptedTokenHandler = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
);

/// A [TokenStorage] implementation backed by `flutter_secure_storage`.
class SecureTokenStorage<T> implements TokenStorage<T> {
  /// Creates a [SecureTokenStorage].
  SecureTokenStorage({
    required FlutterSecureStorage storage,
    required TokenCodec<T> codec,
    required this.storageKey,
    this.schemaVersion = defaultSchemaVersion,
    List<StorageMigration> migrations = const [],
    List<LegacyTokenReader<T>> legacyReaders = const [],
    this.onCorruptedToken,
  })  : assert(schemaVersion > 0, 'schemaVersion must be greater than zero.'),
        _storage = storage,
        _codec = codec,
        _migrations = List<StorageMigration>.unmodifiable(migrations),
        _legacyReaders =
            List<LegacyTokenReader<T>>.unmodifiable(legacyReaders) {
    _validateMigrations();
  }

  /// The default schema version used by newly written payloads.
  static const int defaultSchemaVersion = 1;

  final FlutterSecureStorage _storage;
  final TokenCodec<T> _codec;
  final List<StorageMigration> _migrations;
  final List<LegacyTokenReader<T>> _legacyReaders;

  /// The key used to persist the token.
  final String storageKey;

  /// The schema version written for newly stored tokens.
  final int schemaVersion;

  /// Invoked when the active storage entry cannot be decoded and gets cleared.
  final CorruptedTokenHandler? onCorruptedToken;

  @override
  Future<T?> read() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return _tryReadLegacy();

    try {
      final envelope = _decodeEnvelope(raw);
      final migratedPayload = _migratePayload(
        payload: envelope.payload,
        fromVersion: envelope.schemaVersion,
      );
      final token = _codec.decode(migratedPayload.payload);
      if (migratedPayload.didMigrate) {
        await write(token);
      }
      return token;
    } catch (error, stackTrace) {
      final legacyToken = await _tryReadLegacy();
      if (legacyToken != null) return legacyToken;

      await _storage.delete(key: storageKey);
      final handler = onCorruptedToken;
      if (handler != null) {
        await Future<void>.value(handler(error, stackTrace));
      }
      return null;
    }
  }

  @override
  Future<void> write(T token) async {
    final payload = _codec.encode(token);
    final envelope = <String, Object?>{
      'schemaVersion': schemaVersion,
      'payload': payload,
    };
    await _storage.write(
      key: storageKey,
      value: jsonEncode(envelope),
    );
  }

  @override
  Future<void> delete() {
    return _storage.delete(key: storageKey);
  }

  Future<T?> _tryReadLegacy() async {
    for (final reader in _legacyReaders) {
      try {
        final result = await reader.read();
        if (result == null) continue;

        await write(result.token);
        await result.runCleanup();
        return result.token;
      } catch (error, stackTrace) {
        final handler = onCorruptedToken;
        if (handler != null) {
          await Future<void>.value(handler(error, stackTrace));
        }
      }
    }
    return null;
  }

  _StorageEnvelope _decodeEnvelope(String rawValue) {
    final decodedValue = jsonDecode(rawValue);
    if (decodedValue is! Map<Object?, Object?>) {
      throw const FormatException(
        'Stored token envelope must decode to a JSON object.',
      );
    }

    final envelope = _castJsonMap(decodedValue);
    final schemaVersionValue = envelope['schemaVersion'];
    if (schemaVersionValue is! int) {
      throw const FormatException(
        'Stored token envelope must contain an integer schemaVersion.',
      );
    }

    final payloadValue = envelope['payload'];
    if (payloadValue is! Map<Object?, Object?>) {
      throw const FormatException(
        'Stored token envelope must contain a JSON object payload.',
      );
    }

    return _StorageEnvelope(
      schemaVersion: schemaVersionValue,
      payload: _castJsonMap(payloadValue),
    );
  }

  _MigrationResult _migratePayload({
    required Map<String, Object?> payload,
    required int fromVersion,
  }) {
    if (fromVersion <= 0) {
      throw const FormatException('Stored schemaVersion must be positive.');
    }
    if (fromVersion > schemaVersion) {
      throw FormatException(
        'Stored schemaVersion $fromVersion is newer than supported '
        'schemaVersion $schemaVersion.',
      );
    }

    var currentVersion = fromVersion;
    var currentPayload = payload;
    var didMigrate = false;

    while (currentVersion < schemaVersion) {
      final migration = _migrationFor(currentVersion);
      if (migration == null) {
        throw StateError(
          'Missing migration from schema version $currentVersion.',
        );
      }
      currentPayload = migration.migrate(currentPayload);
      currentVersion = migration.toVersion;
      didMigrate = true;
    }

    return _MigrationResult(
      payload: currentPayload,
      didMigrate: didMigrate,
    );
  }

  StorageMigration? _migrationFor(int fromVersion) {
    for (final migration in _migrations) {
      if (migration.fromVersion == fromVersion) {
        return migration;
      }
    }
    return null;
  }

  void _validateMigrations() {
    final seenVersions = <int>{};
    for (final migration in _migrations) {
      if (migration.fromVersion <= 0) {
        throw ArgumentError.value(
          migration.fromVersion,
          'migrations',
          'Migration fromVersion must be greater than zero.',
        );
      }
      if (migration.toVersion <= migration.fromVersion) {
        throw ArgumentError.value(
          migration.toVersion,
          'migrations',
          'Migration toVersion must be greater than fromVersion.',
        );
      }
      final wasAdded = seenVersions.add(migration.fromVersion);
      if (!wasAdded) {
        throw ArgumentError.value(
          migration.fromVersion,
          'migrations',
          'Only one migration per fromVersion is allowed.',
        );
      }
    }
  }
}

final class _StorageEnvelope {
  const _StorageEnvelope({
    required this.schemaVersion,
    required this.payload,
  });

  final int schemaVersion;
  final Map<String, Object?> payload;
}

final class _MigrationResult {
  const _MigrationResult({
    required this.payload,
    required this.didMigrate,
  });

  final Map<String, Object?> payload;
  final bool didMigrate;
}

Map<String, Object?> _castJsonMap(Map<Object?, Object?> value) {
  return Map<String, Object?>.from(value);
}
