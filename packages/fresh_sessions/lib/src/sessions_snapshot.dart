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
  /// optional [activeSessionId].
  const SessionsSnapshot({
    this.sessions = const [],
    this.activeSessionId,
  });

  /// Creates a [SessionsSnapshot] from a JSON map.
  ///
  /// Throws [FormatException] if the `sessions` field is missing
  /// or malformed.
  factory SessionsSnapshot.fromJson(Map<String, Object?> json) {
    final activeSessionId = json['activeSessionId'] as String?;
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
      activeSessionId: activeSessionId,
      sessions: sessions,
    );
  }

  /// An empty snapshot with no sessions.
  static const empty = SessionsSnapshot();

  /// All registered sessions.
  final List<FreshSession> sessions;

  /// The [FreshSession.id] of the currently active session, or
  /// null if no session is active.
  final String? activeSessionId;

  /// The currently active [FreshSession], resolved from [sessions].
  FreshSession? get activeSession {
    if (activeSessionId == null) return null;
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return null;
  }

  /// Serializes this snapshot to a JSON-safe map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'activeSessionId': activeSessionId,
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
    String? Function()? activeSessionId,
  }) {
    return SessionsSnapshot(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId != null
          ? activeSessionId()
          : this.activeSessionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionsSnapshot &&
          activeSessionId == other.activeSessionId &&
          _listEquals(sessions, other.sessions);

  @override
  int get hashCode =>
      Object.hash(activeSessionId, Object.hashAll(sessions));

  @override
  String toString() =>
      'SessionsSnapshot(sessions: ${sessions.length}, '
      'activeSessionId: $activeSessionId)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
