/// The user's current decision on the local notification permission, as
/// reported by the underlying OS.
enum NotificationPermissionStatus {
  /// The user hasn't been asked yet, so the OS hasn't recorded an answer.
  ///
  /// Scheduling is skipped in this state rather than assumed to be
  /// allowed -- [notDetermined] is also the state reported on platforms
  /// (e.g. Windows) that don't expose a queryable permission at all, since
  /// there's no way to distinguish "not asked" from "not applicable" there.
  notDetermined,

  /// Notifications are allowed to be shown.
  granted,

  /// The user explicitly declined, or disabled notifications in system
  /// settings.
  denied,
}
