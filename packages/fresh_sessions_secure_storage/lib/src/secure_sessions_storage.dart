import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh_sessions/fresh_sessions.dart';

/// Callback invoked when the stored sessions payload cannot be decoded.
typedef CorruptedSessionsHandler = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
);

/// A [SessionsStorage] implementation backed by
/// `flutter_secure_storage`.
///
/// Stores the entire [SessionsSnapshot] as a single JSON document
/// under [storageKey]. Uses a versioned envelope for forward
/// compatibility:
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "payload": {
///     "activeUserId": "u1",
///     "sessions": [...]
///   }
/// }
/// ```
class SecureSessionsStorage implements SessionsStorage {
  /// Creates a [SecureSessionsStorage].
  ///
  /// [storage] defaults to a new [FlutterSecureStorage] instance.
  /// [storageKey] is the key under which the snapshot is persisted.
  SecureSessionsStorage({
    FlutterSecureStorage? storage,
    this.storageKey = defaultStorageKey,
    this.onCorruptedSessions,
  }) : _storage = storage ?? const FlutterSecureStorage();

  /// The default storage key used when none is provided.
  static const String defaultStorageKey = 'fresh_sessions';

  /// The schema version written into every envelope.
  static const int schemaVersion = 1;

  final FlutterSecureStorage _storage;

  /// The key used to persist the sessions snapshot.
  final String storageKey;

  /// Invoked when the stored payload cannot be decoded and is
  /// discarded.
  final CorruptedSessionsHandler? onCorruptedSessions;

  @override
  Future<SessionsSnapshot?> read() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;

    try {
      return _decodeEnvelope(raw);
    } catch (error, stackTrace) {
      await _storage.delete(key: storageKey);
      final handler = onCorruptedSessions;
      if (handler != null) {
        await Future<void>.value(handler(error, stackTrace));
      }
      return null;
    }
  }

  @override
  Future<void> write(SessionsSnapshot snapshot) async {
    final envelope = <String, Object?>{
      'schemaVersion': schemaVersion,
      'payload': snapshot.toJson(),
    };
    await _storage.write(
      key: storageKey,
      value: jsonEncode(envelope),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: storageKey);

  // -----------------------------------------------------------
  // Envelope
  // -----------------------------------------------------------

  static SessionsSnapshot _decodeEnvelope(String rawValue) {
    final decoded = jsonDecode(rawValue);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException(
        'Sessions envelope must be a JSON object.',
      );
    }

    final envelope = Map<String, Object?>.from(decoded);

    final version = envelope['schemaVersion'];
    if (version is! int || version <= 0) {
      throw const FormatException(
        'Sessions envelope must contain a positive '
        'integer schemaVersion.',
      );
    }
    if (version > schemaVersion) {
      throw FormatException(
        'Stored schemaVersion $version is newer than '
        'supported $schemaVersion.',
      );
    }

    final payloadValue = envelope['payload'];
    if (payloadValue is! Map<Object?, Object?>) {
      throw const FormatException(
        'Sessions envelope must contain a JSON object '
        'payload.',
      );
    }

    return SessionsSnapshot.fromJson(
      Map<String, Object?>.from(payloadValue),
    );
  }
}
