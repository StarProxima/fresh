import 'package:meta/meta.dart';

/// Metadata about a single session without any token information.
///
/// Token lifecycle is managed entirely by `TokenStorage` through
/// the core `fresh` package. This record only tracks identity
/// metadata for the session registry.
@immutable
final class FreshSession {
  /// Creates a [FreshSession] with the given identity metadata.
  const FreshSession({
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a [FreshSession] from a JSON map.
  factory FreshSession.fromJson(Map<String, Object?> json) {
    final userId = json['userId'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];

    if (userId is! String) {
      throw const FormatException(
        'FreshSession JSON must have string "userId".',
      );
    }
    if (createdAt is! String || updatedAt is! String) {
      throw const FormatException(
        'FreshSession JSON must have string '
        '"createdAt" and "updatedAt".',
      );
    }

    return FreshSession(
      userId: userId,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  /// User identity this session belongs to.
  final String userId;

  /// When this session was first created.
  final DateTime createdAt;

  /// When this session was last updated.
  final DateTime updatedAt;

  /// Serializes this session to a JSON-safe map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Returns a copy with the given fields replaced.
  FreshSession copyWith({
    DateTime? updatedAt,
  }) {
    return FreshSession(
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreshSession &&
          userId == other.userId &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(userId, createdAt, updatedAt);

  @override
  String toString() => 'FreshSession(userId: $userId)';
}
