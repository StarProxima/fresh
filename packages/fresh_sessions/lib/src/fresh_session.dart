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
    this.metadata = const {},
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

    final rawMetadata = json['metadata'];
    final metadata = rawMetadata is Map<Object?, Object?>
        ? Map<String, Object?>.from(rawMetadata)
        : const <String, Object?>{};

    return FreshSession(
      userId: userId,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      metadata: metadata,
    );
  }

  /// User identity this session belongs to.
  final String userId;

  /// When this session was first created.
  final DateTime createdAt;

  /// When this session was last updated.
  final DateTime updatedAt;

  /// Arbitrary user-facing data (name, avatar, email, etc.).
  final Map<String, Object?> metadata;

  /// Serializes this session to a JSON-safe map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  /// Returns a copy with the given fields replaced.
  FreshSession copyWith({
    DateTime? updatedAt,
    Map<String, Object?>? metadata,
  }) {
    return FreshSession(
      userId: userId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreshSession &&
          userId == other.userId &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(
        userId,
        createdAt,
        updatedAt,
        Object.hashAll(metadata.entries),
      );

  @override
  String toString() => 'FreshSession(userId: $userId)';
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
