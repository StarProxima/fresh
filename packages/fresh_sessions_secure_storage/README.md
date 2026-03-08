# fresh_sessions_secure_storage

Secure [SessionsStorage](https://pub.dev/packages/fresh_sessions) implementation backed by [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage).

## Usage

```dart
import 'package:fresh_sessions/fresh_sessions.dart';
import 'package:fresh_sessions_secure_storage/fresh_sessions_secure_storage.dart';

final sessionsStorage = SecureSessionsStorage();

final controller = FreshSessionController<MyFresh, MyToken>(
  sessionsStorage: sessionsStorage,
  tokenStorageBuilder: (sessionId) => MyTokenStorage(sessionId),
  freshBuilder: (tokenStorage) => MyFresh(tokenStorage: tokenStorage),
);

await controller.ready;
```

The snapshot is stored as a single JSON document under a configurable key (default: `fresh_sessions`). A versioned envelope is used for forward compatibility.

### Custom storage key

```dart
final sessionsStorage = SecureSessionsStorage(
  storageKey: 'my_app_sessions',
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
