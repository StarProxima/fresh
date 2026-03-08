# fresh_sessions

Multi-session orchestration for [fresh](https://pub.dev/packages/fresh).

Manages a registry of user sessions, tracks which one is active, and rebuilds the `Fresh` instance automatically on session switch.

## Key ideas

- **No token in session metadata.** `FreshSession` stores only identity info (`userId`, `environment`). Token lifecycle is fully owned by `TokenStorage` from core `fresh`.
- **Atomic snapshot persistence.** The entire session list + active session id are persisted together via `SessionsStorage` to avoid split-state bugs.
- **Fresh instance per session.** Switching the active session always creates a new `FreshMixin` instance because `FreshMixin` caches the token and in-flight refresh future internally.

## Usage

```dart
// 1. Create a SessionsStorage (in-memory or your own persistent impl)
final sessionsStorage = InMemorySessionsStorage();

// 2. Create the controller
final controller = FreshSessionController<Fresh<MyToken>, MyToken>(
  sessionsStorage: sessionsStorage,
  tokenStorageBuilder: (sessionId) => MyTokenStorage(sessionId),
  freshBuilder: (tokenStorage) => Fresh<MyToken>(
    tokenStorage: tokenStorage,
    refreshToken: (token, client) async => refreshMyToken(token),
    tokenHeader: (token) => {'Authorization': 'Bearer ${token.accessToken}'},
  ),
);

// 3. Wait for hydration
await controller.ready;

// 4. Create a session (writes token, builds Fresh)
await controller.createSession(
  myToken,
  userId: 'user-123',
  environment: 'production',
);

// 5. Access the current Fresh instance
final fresh = controller.fresh; // Fresh<MyToken>?

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
| `FreshSession` | Immutable session metadata (id, userId, environment, timestamps) |
| `SessionsSnapshot` | Atomic snapshot of all sessions + active session id |
| `SessionsStorage` | Persistence contract (read/write/clear snapshot) |
| `InMemorySessionsStorage` | In-memory implementation for testing |
| `FreshSessionController<F, T>` | Orchestration facade |
