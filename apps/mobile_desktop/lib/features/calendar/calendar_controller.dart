import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_event.dart';
import 'calendar_repository.dart';
import 'create_calendar_event_input.dart';

/// Loads and holds the authenticated user's calendar events.
///
/// Exposes loading/data/error via [AsyncValue] so the UI reacts to each
/// state without manual bookkeeping.
class CalendarController extends AsyncNotifier<List<CalendarEvent>> {
  bool _isCreating = false;

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
      final insertIndex = current.indexWhere(
        (event) => event.startAt.isAfter(created.startAt),
      );
      current.insert(insertIndex == -1 ? current.length : insertIndex, created);
      state = AsyncValue.data(current);
    } finally {
      _isCreating = false;
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
