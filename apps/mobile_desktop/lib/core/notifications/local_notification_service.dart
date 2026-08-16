import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/reminders/reminder.dart';
import 'notification_id_mapper.dart';
import 'notification_payload.dart';
import 'notification_permission_state.dart';
import 'notification_plugin_gateway.dart';

/// Device-side delivery for pending reminders, via local (not push)
/// notifications.
///
/// Architecture note: the backend `Reminder` (see
/// `features/reminders/reminder.dart`) stays the single source of truth --
/// this service never invents or persists reminder data of its own. It only
/// decides, from an already-fetched [Reminder], whether/when/what to show
/// on this device, and forgets everything else. [RemindersRepository] is
/// untouched by (and unaware of) this service; the two are wired together
/// only in `RemindersController`, after a backend mutation has already
/// succeeded.
///
/// Depending on the `Reminder` type here (a feature-layer model) instead of
/// staying feature-agnostic is a deliberate exception to the usual
/// core-doesn't-depend-on-features layering: the task this service was
/// built for specifies `scheduleReminder(Reminder reminder)` etc. as its
/// public API, and Reminders is presently the only feature that needs local
/// notifications.
class LocalNotificationService {
  LocalNotificationService({NotificationPluginGateway? gateway})
    : _gateway = gateway ?? FlutterLocalNotificationsGateway();

  /// The app-wide instance, initialized once in `AppBootstrap` before
  /// `runApp` (mirroring how `Supabase.instance.client` is set up). Tests
  /// should construct their own `LocalNotificationService(gateway: ...)`
  /// instead of touching this singleton.
  static final LocalNotificationService instance = LocalNotificationService();

  final NotificationPluginGateway _gateway;
  final _tapController = StreamController<NotificationPayload>.broadcast();
  bool _initialized = false;
  NotificationPayload? _initialLaunchPayload;

  /// Emits the payload of a reminder notification the user tapped, so the
  /// UI can react (e.g. switch to the Reminders tab). The app has no
  /// deep-link routing infrastructure yet, so this intentionally stays a
  /// simple broadcast stream rather than a full routing system.
  ///
  /// This only covers taps that occur while the process is alive
  /// (foreground or backgrounded). A tap that cold-starts a fully
  /// terminated app is captured separately by [initialize] and surfaced
  /// through [consumeInitialLaunchPayload] instead, since it happens before
  /// any widget (and so before anything could be listening to this stream)
  /// exists.
  Stream<NotificationPayload> get onNotificationTapped => _tapController.stream;

  /// Sets up the plugin for Android/iOS/macOS/Windows. Must run before any
  /// scheduling call, and must NOT prompt the user for permission --
  /// [requestPermission] is the explicit, contextual entry point for that.
  ///
  /// Also captures whether *this* app process was cold-started by tapping
  /// one of our reminder notifications, so [consumeInitialLaunchPayload]
  /// can hand it to the UI once it's ready -- this must happen here, before
  /// `runApp`, because the OS only reports launch details once and they'd
  /// otherwise be unreachable by the time any widget mounts.
  Future<void> initialize() async {
    if (_initialized) return;
    await _gateway.initialize(
      onNotificationTapped: (raw) {
        final payload = NotificationPayload.decode(raw);
        if (payload != null) _tapController.add(payload);
      },
    );
    _initialLaunchPayload = await _readLaunchPayload();
    _initialized = true;
  }

  Future<NotificationPayload?> _readLaunchPayload() async {
    try {
      return NotificationPayload.decode(await _gateway.getLaunchPayload());
    } catch (_) {
      // A launch-details lookup failure must never block app startup --
      // this simply means cold-start routing is skipped for this launch.
      return null;
    }
  }

  /// Returns the reminder notification payload that cold-started this app
  /// process, if any, and clears it so subsequent calls return `null`.
  ///
  /// Call this once, as early as the consuming UI (`HomeShell`) is ready to
  /// act on it -- typically from `initState`. The one-shot "consume"
  /// semantics (rather than a plain getter) are what guarantee the initial
  /// launch intent is acted on exactly once, even if the caller is rebuilt.
  NotificationPayload? consumeInitialLaunchPayload() {
    final payload = _initialLaunchPayload;
    _initialLaunchPayload = null;
    return payload;
  }

  Future<NotificationPermissionStatus> getPermissionStatus() =>
      _gateway.getPermissionStatus();

  /// Explicitly prompts for notification permission. Only call this in
  /// direct response to user intent (e.g. right before creating their first
  /// reminder) -- never automatically on startup. Safe to call again after
  /// a denial: the OS itself is responsible for not re-prompting the user
  /// once they've made a decision, so this never bypasses that.
  Future<NotificationPermissionStatus> requestPermission() =>
      _gateway.requestPermission();

  /// Whether the current platform can offer a shortcut into the system
  /// notification settings screen.
  bool get canOpenNotificationSettings => _gateway.canOpenNotificationSettings;

  Future<void> openNotificationSettings() =>
      _gateway.openNotificationSettings();

  /// Schedules a local notification for [reminder], if and only if it's
  /// still actionable: `pending`, due in the future, and permission is
  /// currently granted. Silently does nothing otherwise -- callers don't
  /// need to pre-check these conditions themselves.
  ///
  /// Uses `reminder.remindAt` (the backend's authoritative value) as-is;
  /// never recomputed client-side.
  Future<void> scheduleReminder(Reminder reminder) async {
    if (!_isSchedulable(reminder)) return;
    if (await getPermissionStatus() != NotificationPermissionStatus.granted) {
      return;
    }

    final useExact = await _gateway.canScheduleExactAlarms();
    await _gateway.scheduleAt(
      id: reminderNotificationId(reminder.id),
      title: reminder.title,
      body: _bodyFor(reminder),
      remindAtUtc: reminder.remindAt,
      payload: NotificationPayload(
        reminderId: reminder.id,
        taskId: reminder.taskId,
        calendarEventId: reminder.calendarEventId,
      ).encode(),
      useExactScheduling: useExact,
    );
  }

  /// Removes any local notification scheduled for [reminderId]. Safe to
  /// call even if nothing was ever scheduled for it.
  Future<void> cancelReminder(String reminderId) =>
      _gateway.cancel(reminderNotificationId(reminderId));

  /// Cancels [reminder]'s previous local schedule (if any) and re-schedules
  /// it from its current state. Used after an edit, and as the correction
  /// mechanism during reconciliation.
  Future<void> rescheduleReminder(Reminder reminder) async {
    await cancelReminder(reminder.id);
    await scheduleReminder(reminder);
  }

  /// Brings this device's local notification schedule back in sync with
  /// [reminders] (the full list just loaded from the backend, of any
  /// status).
  ///
  /// Needed after: an app restart (all local schedules were lost), a
  /// Calendar-relative reminder moved server-side, a reminder edited
  /// through another device, or a reminder cancelled/triggered/deleted
  /// elsewhere. For every reminder that should currently be scheduled, this
  /// unconditionally cancels + re-schedules from backend state rather than
  /// trying to compare the previously scheduled fire time (not reliably
  /// obtainable across all four platforms) -- cancel-then-reschedule is
  /// idempotent and always correct, at the cost of a redundant call when
  /// nothing actually changed.
  ///
  /// Only ever touches notification IDs whose payload decodes as a
  /// [NotificationPayload] (i.e. was scheduled by this subsystem);
  /// anything else -- a future AndresAI feature's own local notifications
  /// -- is left completely alone. `cancelAll()` is deliberately never used.
  Future<void> reconcilePendingReminders(List<Reminder> reminders) async {
    final knownNotificationIds = {
      for (final reminder in reminders) reminderNotificationId(reminder.id),
    };

    final pending = await _gateway.pendingNotifications();
    for (final scheduled in pending) {
      final payload = NotificationPayload.decode(scheduled.payload);
      if (payload == null) continue; // Not ours; never touch it.

      final isOrphaned = !knownNotificationIds.contains(scheduled.id);
      if (isOrphaned) {
        // The reminder this notification was scheduled for no longer
        // exists in the backend's loaded list at all (e.g. deleted while
        // the app wasn't running).
        await _safely(() => _gateway.cancel(scheduled.id));
      }
    }

    for (final reminder in reminders) {
      // Each reminder is reconciled independently: one failure (e.g. a
      // transient platform-channel error) must not stop the rest from
      // being corrected.
      await _safely(() async {
        if (_isSchedulable(reminder)) {
          await rescheduleReminder(reminder);
        } else {
          await cancelReminder(reminder.id);
        }
      });
    }
  }

  bool _isSchedulable(Reminder reminder) {
    if (reminder.status != ReminderStatus.pending) return false;
    // A pending reminder whose remindAt has already passed is a known V0.1
    // edge case (see Phase 4.10 spec, section 9): it must not be scheduled
    // locally, but its backend status/data must not be touched here either
    // -- handling that remains a later backend/scheduler concern.
    if (!reminder.remindAt.isAfter(DateTime.now())) return false;
    return true;
  }

  String _bodyFor(Reminder reminder) {
    if (reminder.calendarEventId != null) return 'Calendar reminder';
    if (reminder.taskId != null) return 'Task reminder';
    return 'Reminder';
  }

  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Local notification delivery is best-effort and device-side only;
      // a failure here must never propagate into reminder business logic.
    }
  }

  void dispose() {
    _tapController.close();
  }

  // IDs reserved for debugRunDiagnostics(), well outside the 31-bit range
  // reminderNotificationId() can ever produce (it masks to 0x7FFFFFFF, but
  // in practice hashes of real UUIDs land nowhere near these round
  // values), so a diagnostic run can never collide with a real reminder's
  // scheduled notification.
  @visibleForTesting
  static const debugImmediateNotificationId = 900000001;
  @visibleForTesting
  static const debugScheduledNotificationId = 900000002;

  /// Debug-only diagnostic for investigating "reminder created but no
  /// notification appears" reports. Not called from any production code
  /// path -- wire it to a temporary debug affordance (e.g. a
  /// `kDebugMode`-gated button) while diagnosing, per Phase 4.10.1.
  ///
  /// Shows an immediate test notification (isolates whether the platform's
  /// notification pipeline works at all) and schedules a second one
  /// [testDelay] from now (isolates scheduling/timezone specifically),
  /// logging every value relevant to the investigation: permission status,
  /// `remindAt`, `DateTime.now()`, the notification IDs used, and whether
  /// `pendingNotificationRequests()` reports the scheduled one immediately
  /// after scheduling it. Actual delivery/on-screen presentation still has
  /// to be confirmed by a human watching the device -- this only confirms
  /// what our code did, not what the OS did with it.
  Future<void> debugRunDiagnostics({
    Duration testDelay = const Duration(minutes: 2),
  }) async {
    if (!kDebugMode) return;

    final status = await getPermissionStatus();
    debugPrint('[notif-diagnostic] permission status: $status');
    if (status != NotificationPermissionStatus.granted) {
      debugPrint(
        '[notif-diagnostic] aborting: permission is not granted '
        '(nothing will be scheduled or shown)',
      );
      return;
    }

    debugPrint(
      '[notif-diagnostic] showing an immediate test notification '
      '(id=$debugImmediateNotificationId)',
    );
    await _gateway.showNow(
      id: debugImmediateNotificationId,
      title: 'AndresAI diagnostic (immediate)',
      body:
          'If you see this, immediate local notifications work on this '
          'device.',
      payload: '',
    );

    final now = DateTime.now();
    final remindAtUtc = now.toUtc().add(testDelay);
    debugPrint(
      '[notif-diagnostic] scheduling a test notification '
      '(id=$debugScheduledNotificationId): now=$now remindAtUtc=$remindAtUtc '
      '(+${testDelay.inSeconds}s)',
    );
    await _gateway.scheduleAt(
      id: debugScheduledNotificationId,
      title: 'AndresAI diagnostic (scheduled)',
      body:
          'If you see this ~${testDelay.inMinutes} min after it was '
          'created, scheduled local notifications work.',
      remindAtUtc: remindAtUtc,
      payload: '',
      useExactScheduling: await _gateway.canScheduleExactAlarms(),
    );

    final pending = await _gateway.pendingNotifications();
    final isPending = pending.any(
      (request) => request.id == debugScheduledNotificationId,
    );
    debugPrint(
      '[notif-diagnostic] pendingNotifications() reports ${pending.length} '
      'total request(s); the test schedule (id=$debugScheduledNotificationId) '
      'is ${isPending ? '' : 'NOT '}present',
    );
  }
}

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  return LocalNotificationService.instance;
});
