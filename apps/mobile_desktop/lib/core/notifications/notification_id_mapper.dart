/// Deterministically maps a reminder's UUID to the 32-bit integer ID that
/// local notification platform APIs (Android/iOS/macOS/Windows) require.
///
/// `String.hashCode` is deliberately NOT used here: Dart only guarantees
/// it is stable *within a single running isolate* and explicitly allows it
/// to differ across SDK versions or even separate runs. Relying on it would
/// risk silently orphaning a previously scheduled notification -- the same
/// reminder could compute a different local ID after an app restart or an
/// engine/SDK upgrade, leaving the old notification unreachable to cancel
/// and creating a duplicate on reschedule. FNV-1a is used instead: a
/// small, publicly specified, non-cryptographic hash with a fixed
/// algorithm, so the same UUID always produces the same output on every
/// platform and every run.
///
/// Collision risk: the 32-bit FNV-1a output is folded into 31 bits (kept
/// non-negative, since some platforms' notification ID fields are signed
/// 32-bit integers), giving ~2.1 billion possible values. By the birthday
/// bound, a 50% chance of at least one collision appears around ~54,000
/// simultaneously pending reminders -- far beyond any realistic V0.1 usage.
/// A collision would mean two reminders momentarily share one local
/// notification slot (the most recently scheduled one wins that slot); it
/// never affects the backend reminder data, which remains authoritative.
///
/// Kept in its own tiny, dependency-free function so the mapping algorithm
/// can be swapped out later (e.g. for a collision-free scheme backed by
/// local persistence) without touching any other notification code.
int reminderNotificationId(String reminderId) {
  const fnvOffsetBasis = 0x811c9dc5;
  const fnvPrime = 0x01000193;
  const mask32 = 0xFFFFFFFF;

  var hash = fnvOffsetBasis;
  for (final codeUnit in reminderId.codeUnits) {
    hash = (hash ^ codeUnit) & mask32;
    hash = (hash * fnvPrime) & mask32;
  }

  return hash & 0x7FFFFFFF;
}
