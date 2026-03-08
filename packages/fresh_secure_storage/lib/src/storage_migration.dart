/// Migrates a stored token payload from one schema version to another.
abstract interface class StorageMigration {
  /// The schema version this migration can read.
  int get fromVersion;

  /// The schema version this migration produces.
  int get toVersion;

  /// Returns the migrated payload.
  Map<String, Object?> migrate(Map<String, Object?> payload);
}
