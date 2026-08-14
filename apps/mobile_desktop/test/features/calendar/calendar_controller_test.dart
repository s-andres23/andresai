import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_controller.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/calendar/create_calendar_event_input.dart';

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

final _earlyEvent = CalendarEvent(
  id: 'event-early',
  userId: 'user-1',
  title: 'Early event',
  description: null,
  startAt: DateTime.utc(2026, 8, 20, 8),
  endAt: DateTime.utc(2026, 8, 20, 8, 30),
  allDay: false,
  location: null,
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13),
);

final _midEvent = CalendarEvent(
  id: 'event-mid',
  userId: 'user-1',
  title: 'Mid event',
  description: null,
  startAt: DateTime.utc(2026, 8, 20, 9),
  endAt: DateTime.utc(2026, 8, 20, 9, 30),
  allDay: false,
  location: null,
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13),
);

final _lateEvent = CalendarEvent(
  id: 'event-late',
  userId: 'user-1',
  title: 'Late event',
  description: null,
  startAt: DateTime.utc(2026, 8, 20, 10),
  endAt: DateTime.utc(2026, 8, 20, 10, 30),
  allDay: false,
  location: null,
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13),
);

/// A repository that fetches successfully, and whose `createEvent` succeeds,
/// returning [eventToCreate] and recording every call it receives.
class _CreatingCalendarRepository extends CalendarRepository {
  _CreatingCalendarRepository(this._events, this.eventToCreate) : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent eventToCreate;
  int createCallCount = 0;
  CreateCalendarEventInput? lastInput;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async {
    createCallCount++;
    lastInput = input;
    return eventToCreate;
  }
}

/// A repository that fetches successfully but whose `createEvent` always
/// fails.
class _FailingCreateCalendarRepository extends CalendarRepository {
  _FailingCreateCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async {
    throw Exception('create failed');
  }
}

/// A repository whose `createEvent` doesn't resolve until [complete] is
/// called, so tests can assert on behavior while a create is in flight.
class _DelayedCreateCalendarRepository extends CalendarRepository {
  _DelayedCreateCalendarRepository(this._events, this.eventToCreate)
    : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent eventToCreate;
  final _completer = Completer<void>();
  int createCallCount = 0;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async {
    createCallCount++;
    await _completer.future;
    return eventToCreate;
  }

  void complete() => _completer.complete();
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

  test('createEvent inserts before an existing later event', () async {
    final repository = _CreatingCalendarRepository([_event], _earlyEvent);
    final container = ProviderContainer(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .createEvent(
          CreateCalendarEventInput(
            title: _earlyEvent.title,
            startAt: _earlyEvent.startAt,
            endAt: _earlyEvent.endAt,
          ),
        );

    expect(repository.createCallCount, 1);
    expect(container.read(calendarControllerProvider).value, [
      _earlyEvent,
      _event,
    ]);
  });

  test('createEvent inserts between two existing events, keeping ascending '
      'startAt order', () async {
    final repository = _CreatingCalendarRepository([
      _earlyEvent,
      _lateEvent,
    ], _midEvent);
    final container = ProviderContainer(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .createEvent(
          CreateCalendarEventInput(
            title: _midEvent.title,
            startAt: _midEvent.startAt,
            endAt: _midEvent.endAt,
          ),
        );

    expect(container.read(calendarControllerProvider).value, [
      _earlyEvent,
      _midEvent,
      _lateEvent,
    ]);
  });

  test('createEvent appends after an existing earlier event', () async {
    final repository = _CreatingCalendarRepository([_earlyEvent], _lateEvent);
    final container = ProviderContainer(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .createEvent(
          CreateCalendarEventInput(
            title: _lateEvent.title,
            startAt: _lateEvent.startAt,
            endAt: _lateEvent.endAt,
          ),
        );

    expect(container.read(calendarControllerProvider).value, [
      _earlyEvent,
      _lateEvent,
    ]);
  });

  test('createEvent surfaces errors to the caller without wiping the loaded '
      'list', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _FailingCreateCalendarRepository([_event]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);

    await expectLater(
      container
          .read(calendarControllerProvider.notifier)
          .createEvent(
            CreateCalendarEventInput(
              title: 'Bad event',
              startAt: DateTime.utc(2026, 8, 20),
              endAt: DateTime.utc(2026, 8, 20, 1),
            ),
          ),
      throwsException,
    );

    expect(
      container.read(calendarControllerProvider),
      isA<AsyncData<Object?>>(),
    );
    expect(container.read(calendarControllerProvider).value, [_event]);
  });

  test(
    'createEvent ignores a second call while one is already in flight',
    () async {
      final repository = _DelayedCreateCalendarRepository([
        _event,
      ], _earlyEvent);
      final container = ProviderContainer(
        overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(calendarControllerProvider.future);

      final notifier = container.read(calendarControllerProvider.notifier);
      final input = CreateCalendarEventInput(
        title: _earlyEvent.title,
        startAt: _earlyEvent.startAt,
        endAt: _earlyEvent.endAt,
      );
      final first = notifier.createEvent(input);
      final second = notifier.createEvent(input);

      repository.complete();
      await first;
      await second;

      expect(repository.createCallCount, 1);
      expect(container.read(calendarControllerProvider).value, [
        _earlyEvent,
        _event,
      ]);
    },
  );
}
