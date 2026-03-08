# fresh_secure_storage

A secure `TokenStorage<T>` implementation for
[`package:fresh`](https://pub.dev/packages/fresh) built on top of
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage).

## Features

- Secure persistence for any token type supported by a `TokenCodec<T>`
- Built-in `OAuth2TokenCodec` and `OAuth2SecureTokenStorage`
- Versioned storage envelopes for schema migrations
- Legacy readers for backward compatibility with older storage layouts
- Custom token support for app-specific fields like `userId` and `environment`

## Quick Start

```dart
final storage = OAuth2SecureTokenStorage(
  storage: const FlutterSecureStorage(),
  storageKey: 'fresh.token.default',
);
```

Use it with any `fresh` integration:

```dart
final dio = Dio();

dio.interceptors.add(
  Fresh.oAuth2(
    tokenStorage: OAuth2SecureTokenStorage(
      storage: const FlutterSecureStorage(),
      storageKey: 'fresh.token.default',
    ),
    refreshToken: (token, client) async {
      final response = await client.post(
        'https://api.example.com/auth/refresh',
        data: {'refresh_token': token?.refreshToken},
      );

      return OAuth2Token(
        accessToken: response.data['access_token'] as String,
        refreshToken: response.data['refresh_token'] as String?,
        expiresIn: response.data['expires_in'] as int?,
        issuedAt: DateTime.now(),
      );
    },
  ),
);
```

## Custom Tokens

`fresh_secure_storage` does not require domain fields like `userId` or
`environment` to live in `OAuth2Token`. Instead, define your own token model and
codec:

```dart
class AppToken extends Token {
  const AppToken({
    required super.accessToken,
    required this.userId,
    required this.environment,
    super.refreshToken,
    super.tokenType = 'bearer',
  });

  final String userId;
  final String environment;

  @override
  DateTime? get expiresAt => null;
}

class AppTokenCodec implements TokenCodec<AppToken> {
  @override
  Map<String, Object?> encode(AppToken token) {
    return <String, Object?>{
      'accessToken': token.accessToken,
      'refreshToken': token.refreshToken,
      'tokenType': token.tokenType,
      'userId': token.userId,
      'environment': token.environment,
    };
  }

  @override
  AppToken decode(Map<String, Object?> json) {
    return AppToken(
      accessToken: json['accessToken']! as String,
      refreshToken: json['refreshToken'] as String?,
      tokenType: json['tokenType'] as String? ?? 'bearer',
      userId: json['userId']! as String,
      environment: json['environment']! as String,
    );
  }
}
```

## Migrations

New payloads are stored as a versioned envelope:

```json
{
  "schemaVersion": 1,
  "payload": {
    "accessToken": "..."
  }
}
```

Use `StorageMigration` to migrate older payloads:

```dart
final storage = SecureTokenStorage<AppToken>(
  storage: const FlutterSecureStorage(),
  codec: AppTokenCodec(),
  storageKey: 'fresh.token.default',
  schemaVersion: 2,
  migrations: <StorageMigration>[
    AppTokenV1ToV2Migration(),
  ],
);
```

## Legacy Storage

When older apps used a different layout, register `legacyReaders` to recover the
token and rewrite it in the latest format:

```dart
final storage = SecureTokenStorage<AppToken>(
  storage: const FlutterSecureStorage(),
  codec: AppTokenCodec(),
  storageKey: 'fresh.token.default',
  legacyReaders: <LegacyTokenReader<AppToken>>[
    JsonLegacyTokenReader<AppToken>(
      read: () => const FlutterSecureStorage().read(key: 'legacy_auth_token'),
      codec: AppTokenCodec(),
      cleanup: () => const FlutterSecureStorage().delete(
        key: 'legacy_auth_token',
      ),
    ),
  ],
);
```

`fresh_secure_storage` is intentionally single-token. Multi-account and
multi-environment orchestration should live in `fresh_sessions`.
