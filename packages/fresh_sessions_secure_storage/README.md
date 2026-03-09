# fresh_sessions_secure_storage

Secure [SessionsStorage](https://pub.dev/packages/fresh_sessions) implementation backed by [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage).

## Usage

```dart
import 'package:fresh_sessions/fresh_sessions.dart';
import 'package:fresh_sessions_secure_storage/fresh_sessions_secure_storage.dart';
import 'package:fresh_secure_storage/fresh_secure_storage.dart';

const env = String.fromEnvironment('ENV', defaultValue: 'prod');

final sessionsStorage = SecureSessionsStorage(
  storageKey: '${env}_sessions',
);

final controller = FreshSessionController<MyFresh, OAuth2Token>(
  sessionsStorage: sessionsStorage,
  tokenStorageBuilder: (session) => SecureTokenStorage(
    storage: const FlutterSecureStorage(),
    codec: const OAuth2TokenCodec(),
    storageKey: '${env}_${session.userId}_token',
  ),
  freshBuilder: (tokenStorage) => MyFresh(tokenStorage: tokenStorage),
);

await controller.ready;

// Save session with user metadata for account list UI
await controller.saveSession(
  token: myToken,
  userId: 'user-123',
  metadata: {'name': 'John', 'avatarUrl': '...'},
);
```

The snapshot is stored as a single JSON document under a configurable key (default: `fresh_sessions`). A versioned envelope is used for forward compatibility.

### Environment separation

Different environments get completely isolated session registries via `storageKey`:

```dart
// Production sessions
final prodSessions = SecureSessionsStorage(
  storageKey: 'prod_sessions',
);

// Staging sessions
final stagingSessions = SecureSessionsStorage(
  storageKey: 'staging_sessions',
);
```

### Corrupted data handling

```dart
final sessionsStorage = SecureSessionsStorage(
  onCorruptedSessions: (error, stackTrace) {
    log('Sessions data corrupted, resetting: $error');
  },
);
```
