import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/local_notification_service.dart';
import 'package:mobile_desktop/core/notifications/notification_permission_state.dart';
import 'package:mobile_desktop/features/calendar/calendar_date_format.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/reminders/create_reminder_input.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';
import 'package:mobile_desktop/features/reminders/reminders_page.dart';
import 'package:mobile_desktop/features/reminders/reminders_repository.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';

import '../../support/fake_notification_plugin_gateway.dart';

class _FakeRemindersRepository extends RemindersRepository {
  _FakeRemindersRepository([this._reminders = const []]) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;
}

class _FakeTasksRepository extends TasksRepository {
  _FakeTasksRepository([this._tasks = const []]) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;
}

class _FakeCalendarRepository extends CalendarRepository {
  _FakeCalendarRepository([this._events = const []]) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;
}

/// A repository whose `createReminder` succeeds, returning
/// [reminderToCreate] and recording the input it was called with.
class _CreatingRemindersRepository extends RemindersRepository {
  _CreatingRemindersRepository(this._reminders, this.reminderToCreate)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToCreate;
  CreateReminderInput? lastInput;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> createReminder(CreateReminderInput input) async {
    lastInput = input;
    return reminderToCreate;
  }
}

class _CancellingRemindersRepository extends RemindersRepository {
  _CancellingRemindersRepository(this._reminders, this.reminderToReturn)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToReturn;
  int cancelCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> cancelReminder(String reminderId) async {
    cancelCallCount++;
    return reminderToReturn;
  }
}

class _DeletingRemindersRepository extends RemindersRepository {
  _DeletingRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;
  int deleteCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<void> deleteReminder(String reminderId) async {
    deleteCallCount++;
  }
}

Future<void> _pumpRemindersPage(
  WidgetTester tester, {
  required RemindersRepository remindersRepository,
  TasksRepository? tasksRepository,
  CalendarRepository? calendarRepository,
  LocalNotificationService? notificationService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(remindersRepository),
        tasksRepositoryProvider.overrideWithValue(
          tasksRepository ?? _FakeTasksRepository(),
        ),
        calendarRepositoryProvider.overrideWithValue(
          calendarRepository ?? _FakeCalendarRepository(),
        ),
        localNotificationServiceProvider.overrideWithValue(
          // Granted by default so existing flows (opening the create
          // sheet, etc.) aren't interrupted by the permission-explanation
          // dialog; permission-specific tests override this explicitly.
          notificationService ??
              LocalNotificationService(
                gateway: FakeNotificationPluginGateway(),
              ),
        ),
      ],
      child: const MaterialApp(home: RemindersPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCreateReminderSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add reminder'));
  await tester.pumpAndSettle();
}

Future<void> _openReminderMenu(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.byTooltip('Reminder actions').at(index));
  await tester.pumpAndSettle();
}

final _task = Task(
  id: 'task-1',
  userId: 'user-1',
  title: 'Write report',
  description: null,
  status: TaskStatus.open,
  priority: TaskPriority.normal,
  projectId: null,
  goalId: null,
  dueDate: null,
  dueTime: null,
  createdAt: DateTime.utc(2026, 8, 10),
  updatedAt: DateTime.utc(2026, 8, 10),
  completedAt: null,
);

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

Reminder _pendingReminder({
  String id = 'reminder-1',
  String title = 'Call insurance',
  DateTime? remindAt,
}) {
  return Reminder(
    id: id,
    userId: 'user-1',
    taskId: null,
    calendarEventId: null,
    title: title,
    triggerType: ReminderTriggerType.absolute,
    offsetMinutes: null,
    remindAt: remindAt ?? DateTime.utc(2026, 8, 18, 18),
    status: ReminderStatus.pending,
    createdAt: DateTime.utc(2026, 8, 14),
    updatedAt: DateTime.utc(2026, 8, 14),
  );
}

void main() {
  testWidgets('shows an empty state when there are no reminders', (
    tester,
  ) async {
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository(),
    );

    expect(find.text('No reminders yet.'), findsOneWidget);
  });

  testWidgets('shows a pending reminder with its date/time and status', (
    tester,
  ) async {
    final reminder = _pendingReminder();
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository([reminder]),
    );

    expect(find.text('Call insurance'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('create sheet shows the standard fields for a standalone '
      'reminder', (tester) async {
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository(),
    );
    await _openCreateReminderSheet(tester);

    expect(find.text('New reminder'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Event'), findsOneWidget);
    expect(find.text('Remind me at'), findsOneWidget);
    expect(find.text('Create reminder'), findsOneWidget);
    // No parent selected yet, so no parent-specific fields are shown.
    expect(find.byKey(const ValueKey('reminder-task-dropdown')), findsNothing);
    expect(find.byKey(const ValueKey('reminder-event-dropdown')), findsNothing);
  });

  testWidgets('selecting Task shows a task dropdown', (tester) async {
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository(),
      tasksRepository: _FakeTasksRepository([_task]),
    );
    await _openCreateReminderSheet(tester);

    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reminder-task-dropdown')),
      findsOneWidget,
    );
    // Still absolute (task-relative reminders are unsupported), so the
    // date/time picker remains visible.
    expect(find.text('Remind me at'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reminder-offset-dropdown')),
      findsNothing,
    );
  });

  testWidgets(
    'selecting Event and toggling relative hides the date/time picker and '
    'shows the offset dropdown',
    (tester) async {
      await _pumpRemindersPage(
        tester,
        remindersRepository: _FakeRemindersRepository(),
        calendarRepository: _FakeCalendarRepository([_event]),
      );
      await _openCreateReminderSheet(tester);

      await tester.tap(find.text('Event'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reminder-event-dropdown')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SwitchListTile, 'Relative to event start'),
        findsOneWidget,
      );
      // Absolute by default.
      expect(find.text('Remind me at'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reminder-offset-dropdown')),
        findsNothing,
      );

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Relative to event start'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remind me at'), findsNothing);
      expect(
        find.byKey(const ValueKey('reminder-offset-dropdown')),
        findsOneWidget,
      );
    },
  );

  testWidgets('submitting an empty title shows a validation error', (
    tester,
  ) async {
    final repository = _CreatingRemindersRepository(
      const [],
      _pendingReminder(id: 'reminder-created'),
    );
    await _pumpRemindersPage(tester, remindersRepository: repository);
    await _openCreateReminderSheet(tester);

    await tester.tap(find.text('Create reminder'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(repository.lastInput, isNull);
    expect(find.text('New reminder'), findsOneWidget);
  });

  testWidgets(
    'creating a standalone reminder closes the sheet and shows it in the '
    'list',
    (tester) async {
      final created = _pendingReminder(
        id: 'reminder-created',
        title: 'Call insurance',
      );
      final repository = _CreatingRemindersRepository(const [], created);
      await _pumpRemindersPage(tester, remindersRepository: repository);
      await _openCreateReminderSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Call insurance',
      );
      await tester.tap(find.text('Create reminder'));
      await tester.pumpAndSettle();

      expect(repository.lastInput, isNotNull);
      expect(repository.lastInput!.triggerType, ReminderTriggerType.absolute);
      expect(repository.lastInput!.taskId, isNull);
      expect(repository.lastInput!.calendarEventId, isNull);
      expect(find.text('New reminder'), findsNothing);
      expect(find.text('Call insurance'), findsOneWidget);
    },
  );

  testWidgets(
    'creating a relative Calendar reminder sends the selected offset and '
    'event',
    (tester) async {
      final created = Reminder(
        id: 'reminder-created',
        userId: 'user-1',
        taskId: null,
        calendarEventId: _event.id,
        title: 'Team sync',
        triggerType: ReminderTriggerType.relative,
        offsetMinutes: -10,
        remindAt: DateTime.utc(2026, 8, 20, 8, 50),
        status: ReminderStatus.pending,
        createdAt: DateTime.utc(2026, 8, 14),
        updatedAt: DateTime.utc(2026, 8, 14),
      );
      final repository = _CreatingRemindersRepository(const [], created);
      await _pumpRemindersPage(
        tester,
        remindersRepository: repository,
        calendarRepository: _FakeCalendarRepository([_event]),
      );
      await _openCreateReminderSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Team sync',
      );
      await tester.tap(find.text('Event'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('reminder-event-dropdown')));
      await tester.pumpAndSettle();
      // Built with the same formatting helpers the dropdown item uses,
      // rather than a hardcoded string, since the displayed date/time
      // depends on the test environment's local timezone.
      final eventItemLabel =
          '${_event.title} · '
          '${formatCalendarDate(_event.startAt)} '
          '${formatCalendarTime(_event.startAt)}';
      await tester.tap(find.text(eventItemLabel).last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Relative to event start'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create reminder'));
      await tester.pumpAndSettle();

      expect(repository.lastInput!.triggerType, ReminderTriggerType.relative);
      expect(repository.lastInput!.calendarEventId, _event.id);
      // Default preset (first offset option): 10 minutes before.
      expect(repository.lastInput!.offsetMinutes, -10);
    },
  );

  testWidgets('a pending reminder shows edit, cancel, and delete actions', (
    tester,
  ) async {
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository([_pendingReminder()]),
    );

    await _openReminderMenu(tester);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets(
    'a triggered reminder only shows delete (no edit/cancel actions the '
    'backend would reject)',
    (tester) async {
      final triggered = Reminder(
        id: 'reminder-1',
        userId: 'user-1',
        taskId: null,
        calendarEventId: null,
        title: 'Call insurance',
        triggerType: ReminderTriggerType.absolute,
        offsetMinutes: null,
        remindAt: DateTime.utc(2026, 8, 18, 18),
        status: ReminderStatus.triggered,
        createdAt: DateTime.utc(2026, 8, 14),
        updatedAt: DateTime.utc(2026, 8, 14),
      );
      await _pumpRemindersPage(
        tester,
        remindersRepository: _FakeRemindersRepository([triggered]),
      );

      expect(find.text('Triggered'), findsOneWidget);

      await _openReminderMenu(tester);

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'a cancelled reminder only shows delete (no edit/cancel actions the '
    'backend would reject)',
    (tester) async {
      final cancelled = Reminder(
        id: 'reminder-1',
        userId: 'user-1',
        taskId: null,
        calendarEventId: null,
        title: 'Call insurance',
        triggerType: ReminderTriggerType.absolute,
        offsetMinutes: null,
        remindAt: DateTime.utc(2026, 8, 18, 18),
        status: ReminderStatus.cancelled,
        createdAt: DateTime.utc(2026, 8, 14),
        updatedAt: DateTime.utc(2026, 8, 14),
      );
      await _pumpRemindersPage(
        tester,
        remindersRepository: _FakeRemindersRepository([cancelled]),
      );

      await _openReminderMenu(tester);

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets('cancelling a pending reminder updates its status in place', (
    tester,
  ) async {
    final reminder = _pendingReminder();
    final cancelled = Reminder(
      id: reminder.id,
      userId: reminder.userId,
      taskId: null,
      calendarEventId: null,
      title: reminder.title,
      triggerType: reminder.triggerType,
      offsetMinutes: null,
      remindAt: reminder.remindAt,
      status: ReminderStatus.cancelled,
      createdAt: reminder.createdAt,
      updatedAt: DateTime.utc(2026, 8, 15),
    );
    final repository = _CancellingRemindersRepository([reminder], cancelled);
    await _pumpRemindersPage(tester, remindersRepository: repository);

    await _openReminderMenu(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.cancelCallCount, 1);
    expect(find.text('Cancelled'), findsOneWidget);
    // The reminder stays in the list rather than disappearing.
    expect(find.text(reminder.title), findsOneWidget);
  });

  testWidgets('confirming delete removes the reminder from the list', (
    tester,
  ) async {
    final reminder = _pendingReminder();
    final repository = _DeletingRemindersRepository([reminder]);
    await _pumpRemindersPage(tester, remindersRepository: repository);

    await _openReminderMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete reminder?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 1);
    expect(find.text(reminder.title), findsNothing);
    expect(find.text('No reminders yet.'), findsOneWidget);
  });

  testWidgets('edit sheet for an absolute reminder shows a date/time picker', (
    tester,
  ) async {
    final reminder = _pendingReminder();
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository([reminder]),
    );

    await _openReminderMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit reminder'), findsOneWidget);
    final titleField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Title'),
    );
    expect(titleField.controller!.text, 'Call insurance');
    expect(find.text('Remind me at'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reminder-edit-offset-dropdown')),
      findsNothing,
    );
  });

  testWidgets(
    'edit sheet for a relative Calendar reminder shows an offset dropdown '
    'instead of a date/time picker',
    (tester) async {
      final reminder = Reminder(
        id: 'reminder-1',
        userId: 'user-1',
        taskId: null,
        calendarEventId: _event.id,
        title: 'Team sync',
        triggerType: ReminderTriggerType.relative,
        offsetMinutes: -30,
        remindAt: DateTime.utc(2026, 8, 20, 8, 30),
        status: ReminderStatus.pending,
        createdAt: DateTime.utc(2026, 8, 14),
        updatedAt: DateTime.utc(2026, 8, 14),
      );
      await _pumpRemindersPage(
        tester,
        remindersRepository: _FakeRemindersRepository([reminder]),
        calendarRepository: _FakeCalendarRepository([_event]),
      );

      await _openReminderMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reminder-edit-offset-dropdown')),
        findsOneWidget,
      );
      expect(find.text('Remind me at'), findsNothing);
    },
  );

  testWidgets(
    'shows a non-blocking banner when notification permission is denied',
    (tester) async {
      final notificationService = LocalNotificationService(
        gateway: FakeNotificationPluginGateway(
          initialStatus: NotificationPermissionStatus.denied,
        ),
      );
      await _pumpRemindersPage(
        tester,
        remindersRepository: _FakeRemindersRepository(),
        notificationService: notificationService,
      );

      expect(find.textContaining('Notifications are off'), findsOneWidget);
      // Reminders are still fully usable -- the FAB isn't blocked by this.
      expect(find.byTooltip('Add reminder'), findsOneWidget);
    },
  );

  testWidgets('shows no banner once notification permission is granted', (
    tester,
  ) async {
    await _pumpRemindersPage(
      tester,
      remindersRepository: _FakeRemindersRepository(),
    );

    expect(find.textContaining('Notifications are off'), findsNothing);
  });

  testWidgets(
    'shows a contextual explanation before requesting permission the first '
    'time, when permission is undecided',
    (tester) async {
      final gateway = FakeNotificationPluginGateway(
        initialStatus: NotificationPermissionStatus.notDetermined,
      );
      final notificationService = LocalNotificationService(gateway: gateway);
      final repository = _CreatingRemindersRepository(
        const [],
        _pendingReminder(id: 'reminder-created'),
      );
      await _pumpRemindersPage(
        tester,
        remindersRepository: repository,
        notificationService: notificationService,
      );

      await tester.tap(find.byTooltip('Add reminder'));
      await tester.pumpAndSettle();

      expect(find.text('Enable reminder notifications?'), findsOneWidget);

      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();

      expect(find.text('New reminder'), findsOneWidget);
      expect(
        await gateway.getPermissionStatus(),
        NotificationPermissionStatus.granted,
      );
    },
  );

  testWidgets(
    'does not re-show the permission explanation on a second Add tap once '
    'a decision was made',
    (tester) async {
      final gateway = FakeNotificationPluginGateway(
        initialStatus: NotificationPermissionStatus.notDetermined,
      );
      final notificationService = LocalNotificationService(gateway: gateway);
      await _pumpRemindersPage(
        tester,
        remindersRepository: _FakeRemindersRepository(),
        notificationService: notificationService,
      );

      await tester.tap(find.byTooltip('Add reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      // Declining still opens the create sheet (permission is independent
      // of reminder creation); dismiss it by tapping the modal barrier
      // before trying "Add reminder" again.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add reminder'));
      await tester.pumpAndSettle();

      expect(find.text('Enable reminder notifications?'), findsNothing);
    },
  );
}
