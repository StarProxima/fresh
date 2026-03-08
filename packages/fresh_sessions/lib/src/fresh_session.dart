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

  /// Creates a [FreshSession] from a JSON map.
  ///
  /// Throws [FormatException] if required fields are missing or
  /// have wrong types.
  factory FreshSession.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final userId = json['userId'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];

    if (id is! String || userId is! String) {
      throw const FormatException(
        'FreshSession JSON must have string '
        '"id" and "userId".',
      );
    }
    if (createdAt is! String || updatedAt is! String) {
      throw const FormatException(
        'FreshSession JSON must have string '
        '"createdAt" and "updatedAt".',
      );
    }

    return FreshSession(
      id: id,
      userId: userId,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      environment: json['environment'] as String?,
    );
  }

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

  /// Serializes this session to a JSON-safe map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'userId': userId,
      if (environment != null) 'environment': environment,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

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
