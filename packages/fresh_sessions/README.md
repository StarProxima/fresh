# fresh_sessions

Multi-session orchestration for [fresh](https://pub.dev/packages/fresh).

Manages a registry of user sessions, tracks which one is active, and rebuilds the `Fresh` instance automatically on session switch.

## Key ideas

- **Session metadata.** `FreshSession` stores only identity info (`userId`). Token lifecycle is fully owned by `TokenStorage` from core `fresh`.
- **Atomic snapshot persistence.** The entire session list + active user id are persisted together via `SessionsStorage` to avoid split-state bugs.
- **Fresh instance per session.** Switching the active session always creates a new `FreshMixin` instance because `FreshMixin` caches the token and in-flight refresh future internally.
- **Environments via storage keys.** Different environments (production, staging) are handled by separate `SessionsStorage` / `TokenStorage` instances with different `storageKey`, not by a field on the session.

## Usage

```dart
import 'package:fresh_sessions/fresh_sessions.dart';
import 'package:fresh_sessions_secure_storage/fresh_sessions_secure_storage.dart';
import 'package:fresh_secure_storage/fresh_secure_storage.dart';

const env = String.fromEnvironment('ENV', defaultValue: 'prod');

// 1. Sessions storage scoped to the environment
final sessionsStorage = SecureSessionsStorage(
  storageKey: '${env}_sessions',
);

// 2. Create the controller
final controller = FreshSessionController<MyFresh, OAuth2Token>(
  sessionsStorage: sessionsStorage,
  // Token storage scoped to userId (and environment via storageKey prefix)
  tokenStorageBuilder: (session) => SecureTokenStorage(
    storage: const FlutterSecureStorage(),
    codec: const OAuth2TokenCodec(),
    storageKey: '${env}_${session.userId}_token',
  ),
  freshBuilder: (tokenStorage) => MyFresh(tokenStorage: tokenStorage),
);

// 3. Wait for hydration
await controller.ready;

// 4. Save a session (creates or updates, writes token, builds Fresh)
await controller.saveSession(
  token: myOAuth2Token,
  userId: 'user-123',
);

// 5. Access the current Fresh instance
final fresh = controller.fresh; // MyFresh?

// 6. Listen to changes
controller.freshStream.listen((fresh) {
  // new Fresh instance or null
});
controller.activeSessionStream.listen((session) {
  // active FreshSession or null
});

// 7. Switch sessions
await controller.setActiveSession(otherSession);

// 8. Clean up
await controller.close();
```

## API overview

| Type | Role |
|---|---|
| `FreshSession` | Immutable session metadata (userId, timestamps) |
| `SessionsSnapshot` | Atomic snapshot of all sessions + active user id |
| `SessionsStorage` | Persistence contract (read/write/clear snapshot) |
| `InMemorySessionsStorage` | In-memory implementation for testing |
| `FreshSessionController<F, T>` | Orchestration facade |
