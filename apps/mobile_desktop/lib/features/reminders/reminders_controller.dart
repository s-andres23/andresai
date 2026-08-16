import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/local_notification_service.dart';
import 'create_reminder_input.dart';
import 'reminder.dart';
import 'reminders_repository.dart';
import 'update_reminder_input.dart';

/// Loads and holds the authenticated user's reminders.
///
/// Exposes loading/data/error via [AsyncValue] so the UI reacts to each
/// state without manual bookkeeping.
///
/// Local notification scheduling is wired in here, always *after* a backend
/// mutation has already succeeded and `state` has already been updated: a
/// notification failure must never roll back a successful backend mutation
/// or destroy the loaded reminder list, so every notification call below
/// goes through [_notifySafely], which contains the failure to a debug log
/// rather than letting it propagate out of the mutation method.
class RemindersController extends AsyncNotifier<List<Reminder>> {
  bool _isCreating = false;
  final Set<String> _pendingReminderIds = {};

  @override
  Future<List<Reminder>> build() async {
    final reminders = await ref
        .watch(remindersRepositoryProvider)
        .fetchReminders();
    // Brings this device's local notification schedule back in sync with
    // what the backend just returned -- covers app restarts, edits made on
    // another device, and Calendar-relative reminders the backend moved.
    await _notifySafely(
      () => ref
          .read(localNotificationServiceProvider)
          .reconcilePendingReminders(reminders),
    );
    return reminders;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final reminders = await ref
          .read(remindersRepositoryProvider)
          .fetchReminders();
      await _notifySafely(
        () => ref
            .read(localNotificationServiceProvider)
            .reconcilePendingReminders(reminders),
      );
      return reminders;
    });
  }

  /// Creates a reminder and inserts it into the current list, keeping the
  /// list ordered by `remindAt` ascending.
  ///
  /// Guards against duplicate submission with [_isCreating]. On failure the
  /// error is rethrown to the caller (so the UI can show it) rather than
  /// written to [state], which would replace the loaded reminder list with
  /// an error view.
  Future<void> createReminder(CreateReminderInput input) async {
    if (_isCreating) return;
    _isCreating = true;
    try {
      final created = await ref
          .read(remindersRepositoryProvider)
          .createReminder(input);
      final current = List<Reminder>.from(state.value ?? const []);
      _insertSorted(current, created);
      state = AsyncValue.data(current);
      await _notifySafely(
        () => ref
            .read(localNotificationServiceProvider)
            .scheduleReminder(created),
      );
    } finally {
      _isCreating = false;
    }
  }

  /// Updates [reminderId] and re-inserts it at the position matching its
  /// (possibly changed) `remindAt` so the list stays ordered ascending.
  Future<void> updateReminder(String reminderId, UpdateReminderInput input) =>
      _runExclusive(reminderId, () async {
        final updated = await ref
            .read(remindersRepositoryProvider)
            .updateReminder(reminderId, input);
        final current = List<Reminder>.from(state.value ?? const [])
          ..removeWhere((reminder) => reminder.id == updated.id);
        _insertSorted(current, updated);
        state = AsyncValue.data(current);
        await _notifySafely(
          () => ref
              .read(localNotificationServiceProvider)
              .rescheduleReminder(updated),
        );
      });

  /// Cancels [reminderId] and replaces it in place in the loaded list.
  ///
  /// Cancelling never changes `remindAt`, so the list's order is unaffected
  /// and no re-sort is needed.
  Future<void> cancelReminder(String reminderId) =>
      _runExclusive(reminderId, () async {
        final updated = await ref
            .read(remindersRepositoryProvider)
            .cancelReminder(reminderId);
        state = AsyncValue.data([
          for (final reminder in state.value ?? const [])
            if (reminder.id == updated.id) updated else reminder,
        ]);
        await _notifySafely(
          () => ref
              .read(localNotificationServiceProvider)
              .cancelReminder(reminderId),
        );
      });

  /// Deletes [reminderId] and removes it from the loaded list.
  Future<void> deleteReminder(String reminderId) =>
      _runExclusive(reminderId, () async {
        await ref.read(remindersRepositoryProvider).deleteReminder(reminderId);
        state = AsyncValue.data([
          for (final reminder in state.value ?? const [])
            if (reminder.id != reminderId) reminder,
        ]);
        await _notifySafely(
          () => ref
              .read(localNotificationServiceProvider)
              .cancelReminder(reminderId),
        );
      });

  /// Runs [action], containing any thrown error to a debug log rather than
  /// letting it propagate. Local notification delivery is best-effort and
  /// device-side only, so a failure here must never surface as a backend
  /// mutation failure, roll back `state`, or replace the loaded reminder
  /// list with an error view.
  Future<void> _notifySafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Local notification update failed: $error');
    }
  }

  /// Inserts [reminder] into [reminders] at the position matching ascending
  /// `remindAt` order.
  void _insertSorted(List<Reminder> reminders, Reminder reminder) {
    final insertIndex = reminders.indexWhere(
      (existing) => existing.remindAt.isAfter(reminder.remindAt),
    );
    reminders.insert(
      insertIndex == -1 ? reminders.length : insertIndex,
      reminder,
    );
  }

  /// Runs [action] for [reminderId], guarding against concurrent
  /// update/cancel/delete calls on the same reminder with
  /// [_pendingReminderIds] -- different reminders may still mutate in
  /// parallel. On failure the error is rethrown to the caller (so the UI can
  /// show it) rather than written to [state], which would replace the loaded
  /// reminder list with an error view.
  Future<void> _runExclusive(
    String reminderId,
    Future<void> Function() action,
  ) async {
    if (_pendingReminderIds.contains(reminderId)) return;
    _pendingReminderIds.add(reminderId);
    try {
      await action();
    } finally {
      _pendingReminderIds.remove(reminderId);
    }
  }
}

final remindersControllerProvider =
    AsyncNotifierProvider<RemindersController, List<Reminder>>(
      RemindersController.new,
      // Dispose state as soon as nothing watches it (e.g. on sign-out, when
      // RemindersPage unmounts), so reminders never leak between
      // users/sessions.
      isAutoDispose: true,
      // Riverpod retries a failed build with exponential backoff by default;
      // disable that so a failed GET /reminders reaches the UI error state
      // immediately. The Retry button / refresh() remain the user-driven
      // retry mechanism.
      retry: (retryCount, error) => null,
    );
