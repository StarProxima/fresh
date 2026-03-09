# fresh_sessions

Multi-session orchestration for [fresh](https://pub.dev/packages/fresh).

Manages a registry of user sessions, tracks which one is active, and rebuilds the `Fresh` instance automatically on session switch.

## Key ideas

- **No token in session metadata.** `FreshSession` stores only identity info (`userId`) and arbitrary `metadata` (name, avatar, email). Token lifecycle is fully owned by `TokenStorage` from core `fresh`.
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
  tokenStorageBuilder: (session) => SecureTokenStorage(
    storage: const FlutterSecureStorage(),
    codec: const OAuth2TokenCodec(),
    storageKey: '${env}_${session.userId}_token',
  ),
  freshBuilder: (tokenStorage) => MyFresh(tokenStorage: tokenStorage),
);

// 3. Wait for hydration
await controller.ready;

// 4. Save a session with metadata (creates or updates)
await controller.saveSession(
  token: myOAuth2Token,
  userId: 'user-123',
  metadata: {
    'name': 'John Doe',
    'email': 'john@example.com',
    'avatarUrl': 'https://example.com/avatar.png',
  },
);

// 5. Access the current Fresh instance
final fresh = controller.fresh; // MyFresh?

// 6. Show account list using session metadata
for (final session in controller.snapshot.sessions) {
  print('${session.metadata['name']} (${session.userId})');
}

// 7. Read a token for a non-active session (e.g. to fetch profile)
final token = await controller.readToken(someSession);

// 8. Switch sessions
await controller.setActiveSession(otherSession);

// 9. Clean up
await controller.close();
```

## Migrating from single-token storage

If your app previously used a single `TokenStorage` and you're adding
multi-session support, pass `legacySessionReaders` to migrate
existing tokens into sessions on first launch:

```dart
final controller = FreshSessionController<MyFresh, OAuth2Token>(
  sessionsStorage: sessionsStorage,
  tokenStorageBuilder: (session) => myTokenStorage(session),
  freshBuilder: (tokenStorage) => MyFresh(tokenStorage: tokenStorage),
  legacySessionReaders: [
    MyLegacyReader(oldStorage), // implements LegacySessionReader<OAuth2Token>
  ],
);
```

Each reader returns a `LegacySessionResult` with the token, userId,
optional metadata, and an optional cleanup callback. The controller
runs them only when the session registry is empty.

## API overview

| Type | Role |
|---|---|
| `FreshSession` | Immutable session metadata (userId, timestamps, metadata map) |
| `SessionsSnapshot` | Atomic snapshot of all sessions + active user id |
| `SessionsStorage` | Persistence contract (read/write/clear snapshot) |
| `InMemorySessionsStorage` | In-memory implementation for testing |
| `FreshSessionController<F, T>` | Orchestration facade |
| `LegacySessionReader<T>` | Reads tokens from pre-sessions storage for migration |
