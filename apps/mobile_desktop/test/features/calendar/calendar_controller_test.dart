import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_controller.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/calendar/create_calendar_event_input.dart';
import 'package:mobile_desktop/features/calendar/update_calendar_event_input.dart';

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

/// A repository that fetches successfully, and whose `updateEvent` succeeds,
/// returning [eventToReturn] and recording every call.
class _UpdatingCalendarRepository extends CalendarRepository {
  _UpdatingCalendarRepository(this._events, this.eventToReturn) : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent eventToReturn;
  int updateCallCount = 0;
  String? lastEventId;
  UpdateCalendarEventInput? lastInput;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async {
    updateCallCount++;
    lastEventId = eventId;
    lastInput = input;
    return eventToReturn;
  }
}

/// A repository that fetches successfully but whose `updateEvent` always
/// fails.
class _FailingUpdateCalendarRepository extends CalendarRepository {
  _FailingUpdateCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async {
    throw Exception('update failed');
  }
}

/// A repository that fetches successfully, and whose `deleteEvent` succeeds,
/// recording every call.
class _DeletingCalendarRepository extends CalendarRepository {
  _DeletingCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;
  int deleteCallCount = 0;
  String? lastEventId;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<void> deleteEvent(String eventId) async {
    deleteCallCount++;
    lastEventId = eventId;
  }
}

/// A repository that fetches successfully but whose `deleteEvent` always
/// fails.
class _FailingDeleteCalendarRepository extends CalendarRepository {
  _FailingDeleteCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<void> deleteEvent(String eventId) async {
    throw Exception('delete failed');
  }
}

/// A repository whose `updateEvent` and `deleteEvent` don't resolve until
/// [completeUpdate]/[completeDelete] is called, so a test can verify that
/// different mutation types for the same event are mutually exclusive.
class _DelayedMixedMutationCalendarRepository extends CalendarRepository {
  _DelayedMixedMutationCalendarRepository(this._events, this._updateResult)
    : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent _updateResult;
  final _updateCompleter = Completer<void>();
  final _deleteCompleter = Completer<void>();
  int updateCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async {
    updateCallCount++;
    await _updateCompleter.future;
    return _updateResult;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    deleteCallCount++;
    await _deleteCompleter.future;
  }

  void completeUpdate() => _updateCompleter.complete();
  void completeDelete() => _deleteCompleter.complete();
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

  test('updateEvent replaces the matching event in place when its position '
      'is unchanged', () async {
    final updatedEvent = CalendarEvent(
      id: _event.id,
      userId: _event.userId,
      title: 'Team sync (updated)',
      description: _event.description,
      startAt: _event.startAt,
      endAt: _event.endAt,
      allDay: _event.allDay,
      location: _event.location,
      createdAt: _event.createdAt,
      updatedAt: DateTime.utc(2026, 8, 14),
    );
    final repository = _UpdatingCalendarRepository([
      _earlyEvent,
      _event,
    ], updatedEvent);
    final container = ProviderContainer(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    final input = UpdateCalendarEventInput(
      title: 'Team sync (updated)',
      startAt: _event.startAt,
      endAt: _event.endAt,
      allDay: false,
    );
    await container
        .read(calendarControllerProvider.notifier)
        .updateEvent(_event.id, input);

    expect(repository.updateCallCount, 1);
    expect(repository.lastEventId, _event.id);
    expect(container.read(calendarControllerProvider).value, [
      _earlyEvent,
      updatedEvent,
    ]);
  });

  test('updateEvent re-sorts the list when the updated startAt moves the '
      'event to a new position', () async {
    final movedEvent = CalendarEvent(
      id: _event.id,
      userId: _event.userId,
      title: _event.title,
      description: _event.description,
      startAt: DateTime.utc(2026, 8, 20, 7), // now earlier than _earlyEvent
      endAt: DateTime.utc(2026, 8, 20, 7, 30),
      allDay: _event.allDay,
      location: _event.location,
      createdAt: _event.createdAt,
      updatedAt: DateTime.utc(2026, 8, 14),
    );
    final repository = _UpdatingCalendarRepository([
      _earlyEvent,
      _event,
    ], movedEvent);
    final container = ProviderContainer(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .updateEvent(
          _event.id,
          UpdateCalendarEventInput(
            title: movedEvent.title,
            startAt: movedEvent.startAt,
            endAt: movedEvent.endAt,
            allDay: movedEvent.allDay,
          ),
        );

    expect(container.read(calendarControllerProvider).value, [
      movedEvent,
      _earlyEvent,
    ]);
  });

  test('updateEvent surfaces errors to the caller without wiping the loaded '
      'list', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _FailingUpdateCalendarRepository([_event]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);

    await expectLater(
      container
          .read(calendarControllerProvider.notifier)
          .updateEvent(
            _event.id,
            UpdateCalendarEventInput(
              title: 'Bad update',
              startAt: _event.startAt,
              endAt: _event.endAt,
              allDay: false,
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

  test('deleteEvent removes the event from the loaded list', () async {
    final repository = _DeletingCalendarRepository([_earlyEvent, _event]);
    final container = ProviderContainer(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .deleteEvent(_event.id);

    expect(repository.deleteCallCount, 1);
    expect(repository.lastEventId, _event.id);
    expect(container.read(calendarControllerProvider).value, [_earlyEvent]);
  });

  test('deleteEvent surfaces errors to the caller without wiping the loaded '
      'list', () async {
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(
          _FailingDeleteCalendarRepository([_event]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(calendarControllerProvider.future);

    await expectLater(
      container
          .read(calendarControllerProvider.notifier)
          .deleteEvent(_event.id),
      throwsException,
    );

    expect(container.read(calendarControllerProvider).value, [_event]);
  });

  test(
    'a pending update blocks a concurrent delete for the same event',
    () async {
      final updatedEvent = CalendarEvent(
        id: _event.id,
        userId: _event.userId,
        title: 'Team sync (updated)',
        description: _event.description,
        startAt: _event.startAt,
        endAt: _event.endAt,
        allDay: _event.allDay,
        location: _event.location,
        createdAt: _event.createdAt,
        updatedAt: DateTime.utc(2026, 8, 14),
      );
      final repository = _DelayedMixedMutationCalendarRepository([
        _event,
      ], updatedEvent);
      final container = ProviderContainer(
        overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(calendarControllerProvider.future);

      final notifier = container.read(calendarControllerProvider.notifier);
      // Started first, so it wins the guard: the concurrent delete below
      // should be silently ignored rather than racing it.
      final updateFuture = notifier.updateEvent(
        _event.id,
        UpdateCalendarEventInput(
          title: updatedEvent.title,
          startAt: updatedEvent.startAt,
          endAt: updatedEvent.endAt,
          allDay: updatedEvent.allDay,
        ),
      );
      final deleteFuture = notifier.deleteEvent(_event.id);

      repository.completeUpdate();
      repository.completeDelete();
      await updateFuture;
      await deleteFuture;

      expect(repository.updateCallCount, 1);
      expect(repository.deleteCallCount, 0);
      expect(container.read(calendarControllerProvider).value, [updatedEvent]);
    },
  );
}
