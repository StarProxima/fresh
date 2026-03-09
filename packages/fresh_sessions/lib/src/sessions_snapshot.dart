import 'package:fresh_sessions/src/fresh_session.dart';
import 'package:meta/meta.dart';

/// Atomic snapshot of the entire session registry.
///
/// Contains the list of all known sessions and the currently active
/// one. Persisted and restored atomically through `SessionsStorage`
/// to avoid split-state bugs between session list and active
/// session id.
@immutable
final class SessionsSnapshot {
  /// Creates a snapshot with the given [sessions] and
  /// optional [activeUserId].
  const SessionsSnapshot({
    this.sessions = const [],
    this.activeUserId,
  });

  /// Creates a [SessionsSnapshot] from a JSON map.
  ///
  /// Throws [FormatException] if the `sessions` field is missing
  /// or malformed.
  factory SessionsSnapshot.fromJson(Map<String, Object?> json) {
    final activeUserId = json['activeUserId'] as String?;
    final sessionsJson = json['sessions'];
    if (sessionsJson is! List<Object?>) {
      throw const FormatException(
        'SessionsSnapshot JSON must contain a '
        '"sessions" list.',
      );
    }

    final sessions = <FreshSession>[
      for (final item in sessionsJson)
        FreshSession.fromJson(
          Map<String, Object?>.from(
            item! as Map<Object?, Object?>,
          ),
        ),
    ];

    return SessionsSnapshot(
      activeUserId: activeUserId,
      sessions: sessions,
    );
  }

  /// An empty snapshot with no sessions.
  static const empty = SessionsSnapshot();

  /// All registered sessions.
  final List<FreshSession> sessions;

  /// The [FreshSession.userId] of the currently active session, or
  /// null if no session is active.
  final String? activeUserId;

  /// The currently active [FreshSession], resolved from [sessions].
  FreshSession? get activeSession {
    if (activeUserId == null) return null;
    for (final s in sessions) {
      if (s.userId == activeUserId) return s;
    }
    return null;
  }

  /// Serializes this snapshot to a JSON-safe map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'activeUserId': activeUserId,
      'sessions': [
        for (final s in sessions) s.toJson(),
      ],
    };
  }

  /// Whether there are any registered sessions.
  bool get isEmpty => sessions.isEmpty;

  /// Returns a copy with the given fields replaced.
  SessionsSnapshot copyWith({
    List<FreshSession>? sessions,
    String? Function()? activeUserId,
  }) {
    return SessionsSnapshot(
      sessions: sessions ?? this.sessions,
      activeUserId:
          activeUserId != null ? activeUserId() : this.activeUserId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionsSnapshot &&
          activeUserId == other.activeUserId &&
          _listEquals(sessions, other.sessions);

  @override
  int get hashCode => Object.hash(activeUserId, Object.hashAll(sessions));

  @override
  String toString() =>
      'SessionsSnapshot(sessions: ${sessions.length}, '
      'activeUserId: $activeUserId)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
