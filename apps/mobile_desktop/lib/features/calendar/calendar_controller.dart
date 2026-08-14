import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_event.dart';
import 'calendar_repository.dart';
import 'create_calendar_event_input.dart';
import 'update_calendar_event_input.dart';

/// Loads and holds the authenticated user's calendar events.
///
/// Exposes loading/data/error via [AsyncValue] so the UI reacts to each
/// state without manual bookkeeping.
class CalendarController extends AsyncNotifier<List<CalendarEvent>> {
  bool _isCreating = false;
  final Set<String> _pendingEventIds = {};

  @override
  Future<List<CalendarEvent>> build() {
    return ref.watch(calendarRepositoryProvider).fetchEvents();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(calendarRepositoryProvider).fetchEvents(),
    );
  }

  /// Creates an event and inserts it into the current list, keeping the
  /// list ordered by `startAt` ascending.
  ///
  /// Guards against duplicate submission with [_isCreating]. On failure the
  /// error is rethrown to the caller (so the UI can show it) rather than
  /// written to [state], which would replace the loaded event list with an
  /// error view.
  Future<void> createEvent(CreateCalendarEventInput input) async {
    if (_isCreating) return;
    _isCreating = true;
    try {
      final created = await ref
          .read(calendarRepositoryProvider)
          .createEvent(input);
      final current = List<CalendarEvent>.from(state.value ?? const []);
      _insertSorted(current, created);
      state = AsyncValue.data(current);
    } finally {
      _isCreating = false;
    }
  }

  /// Updates [eventId] and replaces it in place in the loaded list,
  /// re-inserting it at the position matching its (possibly changed)
  /// `startAt` so the list stays ordered ascending.
  Future<void> updateEvent(String eventId, UpdateCalendarEventInput input) =>
      _runExclusive(eventId, () async {
        final updated = await ref
            .read(calendarRepositoryProvider)
            .updateEvent(eventId, input);
        final current = List<CalendarEvent>.from(state.value ?? const [])
          ..removeWhere((event) => event.id == updated.id);
        _insertSorted(current, updated);
        state = AsyncValue.data(current);
      });

  /// Deletes [eventId] and removes it from the loaded list.
  Future<void> deleteEvent(String eventId) => _runExclusive(eventId, () async {
    await ref.read(calendarRepositoryProvider).deleteEvent(eventId);
    state = AsyncValue.data([
      for (final event in state.value ?? const [])
        if (event.id != eventId) event,
    ]);
  });

  /// Inserts [event] into [events] at the position matching ascending
  /// `startAt` order.
  void _insertSorted(List<CalendarEvent> events, CalendarEvent event) {
    final insertIndex = events.indexWhere(
      (existing) => existing.startAt.isAfter(event.startAt),
    );
    events.insert(insertIndex == -1 ? events.length : insertIndex, event);
  }

  /// Runs [action] for [eventId], guarding against concurrent update/delete
  /// calls on the same event with [_pendingEventIds]. On failure the error
  /// is rethrown to the caller (so the UI can show it) rather than written
  /// to [state], which would replace the loaded event list with an error
  /// view.
  Future<void> _runExclusive(
    String eventId,
    Future<void> Function() action,
  ) async {
    if (_pendingEventIds.contains(eventId)) return;
    _pendingEventIds.add(eventId);
    try {
      await action();
    } finally {
      _pendingEventIds.remove(eventId);
    }
  }
}

final calendarControllerProvider =
    AsyncNotifierProvider<CalendarController, List<CalendarEvent>>(
      CalendarController.new,
      // Dispose state as soon as nothing watches it (e.g. on sign-out, when
      // CalendarPage unmounts), so events never leak between users/sessions.
      isAutoDispose: true,
      // Riverpod retries a failed build with exponential backoff by default;
      // disable that so a failed GET /calendar-events reaches the UI error
      // state immediately. The Retry button / refresh() remain the
      // user-driven retry mechanism.
      retry: (retryCount, error) => null,
    );
