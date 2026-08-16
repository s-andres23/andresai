import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/local_notification_service.dart';
import 'package:mobile_desktop/core/notifications/notification_id_mapper.dart';
import 'package:mobile_desktop/features/calendar/calendar_controller.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/calendar/update_calendar_event_input.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';
import 'package:mobile_desktop/features/reminders/reminders_controller.dart';
import 'package:mobile_desktop/features/reminders/reminders_repository.dart';

import '../../support/fake_notification_plugin_gateway.dart';

/// Covers the Calendar -> Reminders immediate sync behavior: after a
/// Calendar event's `startAt` is successfully changed, `RemindersController`
/// must be invalidated so the backend's already-recalculated relative
/// reminders (and, through the existing reconciliation path, their local
/// notification schedules) are picked up right away.
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

class _UpdatingCalendarRepository extends CalendarRepository {
  _UpdatingCalendarRepository(this._events, this.eventToReturn) : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent eventToReturn;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async => eventToReturn;
}

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

/// Returns a different reminders list on each successive `fetchReminders()`
/// call (from [responses], clamped to the last entry once exhausted), so a
/// test can simulate the backend having recalculated a relative reminder's
/// `remindAt` between the initial load and a later refresh.
class _SequencedRemindersRepository extends RemindersRepository {
  _SequencedRemindersRepository(this.responses) : super(Dio());

  final List<List<Reminder>> responses;
  int fetchCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async {
    final response = responses[fetchCallCount.clamp(0, responses.length - 1)];
    fetchCallCount++;
    return response;
  }
}

Reminder _relativeReminder({required DateTime remindAt}) {
  return Reminder(
    id: 'reminder-1',
    userId: 'user-1',
    taskId: null,
    calendarEventId: _event.id,
    title: 'Team sync reminder',
    triggerType: ReminderTriggerType.relative,
    offsetMinutes: -15,
    remindAt: remindAt,
    status: ReminderStatus.pending,
    createdAt: DateTime.utc(2026, 8, 13),
    updatedAt: DateTime.utc(2026, 8, 13),
  );
}

void main() {
  test('a Calendar startAt change invalidates RemindersController, triggering '
      'a fresh fetch', () async {
    final moved = CalendarEvent(
      id: _event.id,
      userId: _event.userId,
      title: _event.title,
      description: _event.description,
      startAt: DateTime.utc(2026, 8, 20, 10),
      endAt: DateTime.utc(2026, 8, 20, 10, 30),
      allDay: _event.allDay,
      location: _event.location,
      createdAt: _event.createdAt,
      updatedAt: DateTime.utc(2026, 8, 14),
    );
    final calendarRepository = _UpdatingCalendarRepository([_event], moved);
    final remindersRepository = _SequencedRemindersRepository([const []]);
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(calendarRepository),
        remindersRepositoryProvider.overrideWithValue(remindersRepository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: FakeNotificationPluginGateway()),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Mirrors RemindersPage keeping RemindersController watched (via
    // HomeShell's IndexedStack) for as long as the user is signed in.
    container.listen(remindersControllerProvider, (_, _) {});
    await container.read(remindersControllerProvider.future);
    expect(remindersRepository.fetchCallCount, 1);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .updateEvent(
          _event.id,
          UpdateCalendarEventInput(
            title: moved.title,
            startAt: moved.startAt,
            endAt: moved.endAt,
            allDay: moved.allDay,
          ),
        );
    await container.read(remindersControllerProvider.future);

    expect(remindersRepository.fetchCallCount, 2);
  });

  test('a title/description/location-only Calendar edit does not invalidate '
      'RemindersController', () async {
    final renamed = CalendarEvent(
      id: _event.id,
      userId: _event.userId,
      title: 'Team sync (renamed)',
      description: _event.description,
      startAt: _event.startAt,
      endAt: _event.endAt,
      allDay: _event.allDay,
      location: _event.location,
      createdAt: _event.createdAt,
      updatedAt: DateTime.utc(2026, 8, 14),
    );
    final calendarRepository = _UpdatingCalendarRepository([_event], renamed);
    final remindersRepository = _SequencedRemindersRepository([const []]);
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(calendarRepository),
        remindersRepositoryProvider.overrideWithValue(remindersRepository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: FakeNotificationPluginGateway()),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(remindersControllerProvider, (_, _) {});
    await container.read(remindersControllerProvider.future);
    expect(remindersRepository.fetchCallCount, 1);

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .updateEvent(
          _event.id,
          UpdateCalendarEventInput(
            title: renamed.title,
            startAt: renamed.startAt,
            endAt: renamed.endAt,
            allDay: renamed.allDay,
          ),
        );
    // Let any pending microtasks settle before asserting nothing changed.
    await Future<void>.delayed(Duration.zero);

    expect(remindersRepository.fetchCallCount, 1);
  });

  test(
    'a failed Calendar update does not invalidate RemindersController',
    () async {
      final remindersRepository = _SequencedRemindersRepository([const []]);
      final container = ProviderContainer(
        overrides: [
          calendarRepositoryProvider.overrideWithValue(
            _FailingUpdateCalendarRepository([_event]),
          ),
          remindersRepositoryProvider.overrideWithValue(remindersRepository),
          localNotificationServiceProvider.overrideWithValue(
            LocalNotificationService(gateway: FakeNotificationPluginGateway()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(remindersControllerProvider, (_, _) {});
      await container.read(remindersControllerProvider.future);
      expect(remindersRepository.fetchCallCount, 1);

      await container.read(calendarControllerProvider.future);
      await expectLater(
        container
            .read(calendarControllerProvider.notifier)
            .updateEvent(
              _event.id,
              UpdateCalendarEventInput(
                title: _event.title,
                startAt: DateTime.utc(2026, 8, 20, 11),
                endAt: DateTime.utc(2026, 8, 20, 11, 30),
                allDay: false,
              ),
            ),
        throwsException,
      );
      await Future<void>.delayed(Duration.zero);

      expect(remindersRepository.fetchCallCount, 1);
    },
  );

  test('the refreshed reminder list (reflecting the backend-recalculated '
      'remindAt) is what reconciliation reschedules the local notification '
      'from', () async {
    final moved = CalendarEvent(
      id: _event.id,
      userId: _event.userId,
      title: _event.title,
      description: _event.description,
      startAt: DateTime.utc(2026, 8, 20, 10),
      endAt: DateTime.utc(2026, 8, 20, 10, 30),
      allDay: _event.allDay,
      location: _event.location,
      createdAt: _event.createdAt,
      updatedAt: DateTime.utc(2026, 8, 14),
    );
    // The reminder's remindAt before the Calendar change (offset -15 min
    // from the original 09:00 startAt)...
    final staleReminder = _relativeReminder(
      remindAt: DateTime.utc(2026, 8, 20, 8, 45),
    );
    // ...and what the backend reports it recalculated to once startAt
    // moves to 10:00 (still -15 min offset).
    final recalculatedReminder = _relativeReminder(
      remindAt: DateTime.utc(2026, 8, 20, 9, 45),
    );

    final calendarRepository = _UpdatingCalendarRepository([_event], moved);
    final remindersRepository = _SequencedRemindersRepository([
      [staleReminder],
      [recalculatedReminder],
    ]);
    final gateway = FakeNotificationPluginGateway();
    final container = ProviderContainer(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(calendarRepository),
        remindersRepositoryProvider.overrideWithValue(remindersRepository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(remindersControllerProvider, (_, _) {});
    await container.read(remindersControllerProvider.future);
    final notificationId = reminderNotificationId(staleReminder.id);
    expect(
      gateway.scheduled[notificationId]!.remindAtUtc,
      staleReminder.remindAt,
    );

    await container.read(calendarControllerProvider.future);
    await container
        .read(calendarControllerProvider.notifier)
        .updateEvent(
          _event.id,
          UpdateCalendarEventInput(
            title: moved.title,
            startAt: moved.startAt,
            endAt: moved.endAt,
            allDay: moved.allDay,
          ),
        );
    await container.read(remindersControllerProvider.future);

    expect(
      gateway.scheduled[notificationId]!.remindAtUtc,
      recalculatedReminder.remindAt,
    );
  });
}
