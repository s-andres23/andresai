import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_controller.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';

final _event = CalendarEvent(
  id: 'event-1',
  userId: 'user-1',
  title: 'Team sync',
  description: null,
  startAt: DateTime.utc(2026, 8, 20, 9),
  endAt: DateTime.utc(2026, 8, 20, 9, 30),
  allDay: false,
  location: null,
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13),
);

class _FakeCalendarRepository extends CalendarRepository {
  _FakeCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;
}

class _ThrowingCalendarRepository extends CalendarRepository {
  _ThrowingCalendarRepository() : super(Dio());

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    throw Exception('network error');
  }
}

void main() {
  test('starts in loading state and resolves to the loaded events', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _FakeCalendarRepository([_event]),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(calendarControllerProvider),
      isA<AsyncLoading<Object?>>(),
    );

    final events = await container.read(calendarControllerProvider.future);

    expect(events, [_event]);
    expect(container.read(calendarControllerProvider).value, [_event]);
  });

  test('exposes an error state when the repository throws', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _ThrowingCalendarRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // If automatic retry were still enabled, this would hang for several
    // seconds (Riverpod's default backoff) instead of failing immediately.
    await expectLater(
      container.read(calendarControllerProvider.future),
      throwsException,
    );
    expect(
      container.read(calendarControllerProvider),
      isA<AsyncError<Object?>>(),
    );
  });

  test('refresh() re-fetches events from the repository', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _FakeCalendarRepository([_event]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    await container.read(calendarControllerProvider.notifier).refresh();

    expect(container.read(calendarControllerProvider).value, [_event]);
  });

  test('disposes its state once nothing is watching it', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _FakeCalendarRepository([_event]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      calendarControllerProvider,
      (_, _) {},
    );
    await container.read(calendarControllerProvider.future);
    expect(container.exists(calendarControllerProvider), isTrue);

    // Simulates CalendarPage unmounting, e.g. on sign-out.
    subscription.close();
    await Future<void>.delayed(Duration.zero);

    expect(container.exists(calendarControllerProvider), isFalse);
  });
}
