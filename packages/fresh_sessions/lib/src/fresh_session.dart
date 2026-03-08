import 'package:meta/meta.dart';

/// Metadata about a single session without any token information.
///
/// Token lifecycle is managed entirely by `TokenStorage` through
/// the core `fresh` package. This record only tracks identity
/// and environment metadata for the session registry.
@immutable
final class FreshSession {
  /// Creates a [FreshSession] with the given identity metadata.
  const FreshSession({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.environment,
  });

  /// Unique session identifier, typically derived from
  /// [userId] + [environment].
  final String id;

  /// User identity this session belongs to.
  final String userId;

  /// Logical environment (e.g. "production", "staging").
  ///
  /// When `null`, the session is not environment-specific.
  final String? environment;

  /// When this session was first created.
  final DateTime createdAt;

  /// When this session was last updated.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  FreshSession copyWith({
    String? userId,
    String? environment,
    DateTime? updatedAt,
  }) {
    return FreshSession(
      id: id,
      userId: userId ?? this.userId,
      environment: environment ?? this.environment,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreshSession &&
          id == other.id &&
          userId == other.userId &&
          environment == other.environment &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        userId,
        environment,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'FreshSession(id: $id, userId: $userId, '
      'environment: $environment)';
}
