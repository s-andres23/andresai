import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/local_notification_service.dart';
import 'package:mobile_desktop/core/notifications/notification_id_mapper.dart';
import 'package:mobile_desktop/features/reminders/create_reminder_input.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';
import 'package:mobile_desktop/features/reminders/reminders_controller.dart';
import 'package:mobile_desktop/features/reminders/reminders_repository.dart';
import 'package:mobile_desktop/features/reminders/update_reminder_input.dart';

import '../../support/fake_notification_plugin_gateway.dart';

/// Covers the notification side of `RemindersController`'s mutations --
/// general list/mutation-guard behavior is already covered by
/// `reminders_controller_test.dart`; this file focuses specifically on how
/// each mutation wires into `LocalNotificationService`.
Reminder _reminder({
  String id = 'reminder-1',
  String title = 'Call insurance',
  DateTime? remindAt,
  ReminderStatus status = ReminderStatus.pending,
}) {
  return Reminder(
    id: id,
    userId: 'user-1',
    taskId: null,
    calendarEventId: null,
    title: title,
    triggerType: ReminderTriggerType.absolute,
    offsetMinutes: null,
    remindAt: remindAt ?? DateTime.now().add(const Duration(hours: 1)),
    status: status,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

class _FakeRemindersRepository extends RemindersRepository {
  _FakeRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;
}

class _CreatingRemindersRepository extends RemindersRepository {
  _CreatingRemindersRepository(this._reminders, this.reminderToCreate)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToCreate;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> createReminder(CreateReminderInput input) async =>
      reminderToCreate;
}

class _FailingCreateRemindersRepository extends RemindersRepository {
  _FailingCreateRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> createReminder(CreateReminderInput input) async {
    throw Exception('create failed');
  }
}

class _UpdatingRemindersRepository extends RemindersRepository {
  _UpdatingRemindersRepository(this._reminders, this.reminderToReturn)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToReturn;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> updateReminder(
    String reminderId,
    UpdateReminderInput input,
  ) async => reminderToReturn;
}

class _CancellingRemindersRepository extends RemindersRepository {
  _CancellingRemindersRepository(this._reminders, this.reminderToReturn)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToReturn;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> cancelReminder(String reminderId) async => reminderToReturn;
}

class _DeletingRemindersRepository extends RemindersRepository {
  _DeletingRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<void> deleteReminder(String reminderId) async {}
}

class _ReactivatingRemindersRepository extends RemindersRepository {
  _ReactivatingRemindersRepository(this._reminders, this.reminderToReturn)
    : super(Dio());

  final List<Reminder> _reminders;
  final Reminder reminderToReturn;
  int reactivateCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> reactivateReminder(String reminderId) async {
    reactivateCallCount++;
    return reminderToReturn;
  }
}

class _FailingReactivateRemindersRepository extends RemindersRepository {
  _FailingReactivateRemindersRepository(this._reminders) : super(Dio());

  final List<Reminder> _reminders;

  @override
  Future<List<Reminder>> fetchReminders() async => _reminders;

  @override
  Future<Reminder> reactivateReminder(String reminderId) async {
    throw Exception('reactivate failed: remindAt is in the past');
  }
}

void main() {
  test(
    'a successful create attempts to schedule a local notification',
    () async {
      final gateway = FakeNotificationPluginGateway();
      final created = _reminder(id: 'reminder-created');
      final repository = _CreatingRemindersRepository(const [], created);
      final container = ProviderContainer(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(repository),
          localNotificationServiceProvider.overrideWithValue(
            LocalNotificationService(gateway: gateway),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);
      await container
          .read(remindersControllerProvider.notifier)
          .createReminder(
            CreateReminderInput(
              title: created.title,
              triggerType: created.triggerType,
              remindAt: created.remindAt,
            ),
          );

      expect(gateway.scheduleCallCount, 1);
      expect(gateway.scheduled[reminderNotificationId(created.id)], isNotNull);
    },
  );

  test('a successful update reschedules the local notification from its new '
      'state', () async {
    final gateway = FakeNotificationPluginGateway();
    final reminder = _reminder();
    final updated = _reminder(title: 'Call insurance (renamed)');
    final repository = _UpdatingRemindersRepository([reminder], updated);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    // build() itself reconciles [reminder], which already schedules and
    // cancels once; reset counters so the assertions below only reflect
    // the explicit updateReminder() call.
    await container.read(remindersControllerProvider.future);
    gateway.cancelCalls.clear();
    gateway.scheduleCallCount = 0;

    await container
        .read(remindersControllerProvider.notifier)
        .updateReminder(reminder.id, UpdateReminderInput(title: updated.title));

    expect(gateway.cancelCalls, contains(reminderNotificationId(reminder.id)));
    expect(gateway.scheduleCallCount, 1);
    expect(
      gateway.scheduled[reminderNotificationId(reminder.id)]!.title,
      updated.title,
    );
  });

  test('a successful cancel removes the local notification', () async {
    final gateway = FakeNotificationPluginGateway();
    final reminder = _reminder();
    final cancelled = _reminder(status: ReminderStatus.cancelled);
    final repository = _CancellingRemindersRepository([reminder], cancelled);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    // Sanity check: the pending future reminder was locally scheduled as
    // part of the initial load's reconciliation.
    expect(gateway.scheduled[reminderNotificationId(reminder.id)], isNotNull);

    await container
        .read(remindersControllerProvider.notifier)
        .cancelReminder(reminder.id);

    expect(gateway.cancelCalls, contains(reminderNotificationId(reminder.id)));
    expect(gateway.scheduled[reminderNotificationId(reminder.id)], isNull);
  });

  test('a successful delete removes the local notification', () async {
    final gateway = FakeNotificationPluginGateway();
    final reminder = _reminder();
    final repository = _DeletingRemindersRepository([reminder]);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    expect(gateway.scheduled[reminderNotificationId(reminder.id)], isNotNull);

    await container
        .read(remindersControllerProvider.notifier)
        .deleteReminder(reminder.id);

    expect(gateway.cancelCalls, contains(reminderNotificationId(reminder.id)));
    expect(gateway.scheduled[reminderNotificationId(reminder.id)], isNull);
  });

  test('a notification scheduling exception does not roll back the successful '
      'backend create, nor surface as an error to the caller', () async {
    final gateway = FakeNotificationPluginGateway()..throwOnSchedule = true;
    final created = _reminder(id: 'reminder-created');
    final repository = _CreatingRemindersRepository(const [], created);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    // Must complete without throwing, despite the gateway always failing
    // to schedule.
    await container
        .read(remindersControllerProvider.notifier)
        .createReminder(
          CreateReminderInput(
            title: created.title,
            triggerType: created.triggerType,
            remindAt: created.remindAt,
          ),
        );

    expect(
      container.read(remindersControllerProvider),
      isA<AsyncData<Object?>>(),
    );
    expect(container.read(remindersControllerProvider).value, [created]);
  });

  test(
    'a create failing in the backend never reaches notification scheduling',
    () async {
      final gateway = FakeNotificationPluginGateway();
      final container = ProviderContainer(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(
            _FailingCreateRemindersRepository(const []),
          ),
          localNotificationServiceProvider.overrideWithValue(
            LocalNotificationService(gateway: gateway),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);

      await expectLater(
        container
            .read(remindersControllerProvider.notifier)
            .createReminder(
              CreateReminderInput(
                title: 'Bad reminder',
                triggerType: ReminderTriggerType.absolute,
                remindAt: DateTime.now().add(const Duration(hours: 1)),
              ),
            ),
        throwsException,
      );

      expect(gateway.scheduleCallCount, 0);
    },
  );

  test('build() reconciles the loaded list on startup', () async {
    final gateway = FakeNotificationPluginGateway();
    final futureReminder = _reminder(id: 'reminder-future');
    final pastPending = _reminder(
      id: 'reminder-past',
      remindAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final cancelledReminder = _reminder(
      id: 'reminder-cancelled',
      status: ReminderStatus.cancelled,
    );
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(
          _FakeRemindersRepository([
            futureReminder,
            pastPending,
            cancelledReminder,
          ]),
        ),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    expect(
      gateway.scheduled[reminderNotificationId(futureReminder.id)],
      isNotNull,
    );
    expect(gateway.scheduled[reminderNotificationId(pastPending.id)], isNull);
    expect(
      gateway.scheduled[reminderNotificationId(cancelledReminder.id)],
      isNull,
    );
  });

  test('a successful reactivate replaces the cancelled reminder with the '
      'pending one the backend returns', () async {
    final gateway = FakeNotificationPluginGateway();
    final cancelled = _reminder(status: ReminderStatus.cancelled);
    final reactivated = _reminder();
    final repository = _ReactivatingRemindersRepository([
      cancelled,
    ], reactivated);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .reactivateReminder(cancelled.id);

    expect(repository.reactivateCallCount, 1);
    expect(container.read(remindersControllerProvider).value, [reactivated]);
    expect(
      container.read(remindersControllerProvider).value!.single.status,
      ReminderStatus.pending,
    );
  });

  test(
    're-sorts the list when reactivation returns a changed remindAt (a '
    'relative Calendar reminder recalculated against the current event)',
    () async {
      final gateway = FakeNotificationPluginGateway();
      final earlier = _reminder(
        id: 'reminder-earlier',
        remindAt: DateTime.now().add(const Duration(minutes: 30)),
      );
      final cancelled = _reminder(
        id: 'reminder-cancelled',
        status: ReminderStatus.cancelled,
        remindAt: DateTime.now().add(const Duration(hours: 5)),
      );
      // Reactivation recalculates it to land *before* `earlier`.
      final reactivated = _reminder(
        id: 'reminder-cancelled',
        remindAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      final repository = _ReactivatingRemindersRepository([
        earlier,
        cancelled,
      ], reactivated);
      final container = ProviderContainer(
        overrides: [
          remindersRepositoryProvider.overrideWithValue(repository),
          localNotificationServiceProvider.overrideWithValue(
            LocalNotificationService(gateway: gateway),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(remindersControllerProvider.future);
      await container
          .read(remindersControllerProvider.notifier)
          .reactivateReminder(cancelled.id);

      expect(container.read(remindersControllerProvider).value, [
        reactivated,
        earlier,
      ]);
    },
  );

  test('a successful reactivate schedules a local notification from the '
      'returned reminder', () async {
    final gateway = FakeNotificationPluginGateway();
    final cancelled = _reminder(status: ReminderStatus.cancelled);
    final reactivated = _reminder();
    final repository = _ReactivatingRemindersRepository([
      cancelled,
    ], reactivated);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .reactivateReminder(cancelled.id);

    expect(
      gateway.scheduled[reminderNotificationId(reactivated.id)],
      isNotNull,
    );
  });

  test('a notification scheduling exception during reactivate does not undo '
      'the successful backend reactivation', () async {
    final gateway = FakeNotificationPluginGateway()..throwOnSchedule = true;
    final cancelled = _reminder(status: ReminderStatus.cancelled);
    final reactivated = _reminder();
    final repository = _ReactivatingRemindersRepository([
      cancelled,
    ], reactivated);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);
    await container
        .read(remindersControllerProvider.notifier)
        .reactivateReminder(cancelled.id);

    expect(
      container.read(remindersControllerProvider),
      isA<AsyncData<Object?>>(),
    );
    expect(container.read(remindersControllerProvider).value, [reactivated]);
  });

  test('a failed backend reactivate preserves the loaded state and rethrows '
      'to the caller', () async {
    final gateway = FakeNotificationPluginGateway();
    final cancelled = _reminder(status: ReminderStatus.cancelled);
    final repository = _FailingReactivateRemindersRepository([cancelled]);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    await expectLater(
      container
          .read(remindersControllerProvider.notifier)
          .reactivateReminder(cancelled.id),
      throwsException,
    );

    expect(
      container.read(remindersControllerProvider),
      isA<AsyncData<Object?>>(),
    );
    expect(container.read(remindersControllerProvider).value, [cancelled]);
    expect(gateway.scheduleCallCount, 0);
  });

  test('a second reactivate call for the same reminder while one is already '
      'in flight is ignored', () async {
    final gateway = FakeNotificationPluginGateway();
    final cancelled = _reminder(status: ReminderStatus.cancelled);
    final reactivated = _reminder();
    final repository = _ReactivatingRemindersRepository([
      cancelled,
    ], reactivated);
    final container = ProviderContainer(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repository),
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(gateway: gateway),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(remindersControllerProvider.future);

    final notifier = container.read(remindersControllerProvider.notifier);
    final first = notifier.reactivateReminder(cancelled.id);
    final second = notifier.reactivateReminder(cancelled.id);
    await first;
    await second;

    expect(repository.reactivateCallCount, 1);
  });
}
