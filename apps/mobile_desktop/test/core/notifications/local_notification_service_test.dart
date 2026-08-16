import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/local_notification_service.dart';
import 'package:mobile_desktop/core/notifications/notification_id_mapper.dart';
import 'package:mobile_desktop/core/notifications/notification_permission_state.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';

import '../../support/fake_notification_plugin_gateway.dart';

Reminder _reminder({
  String id = 'reminder-1',
  String title = 'Call insurance',
  DateTime? remindAt,
  ReminderStatus status = ReminderStatus.pending,
  ReminderTriggerType triggerType = ReminderTriggerType.absolute,
  int? offsetMinutes,
  String? taskId,
  String? calendarEventId,
}) {
  return Reminder(
    id: id,
    userId: 'user-1',
    taskId: taskId,
    calendarEventId: calendarEventId,
    title: title,
    triggerType: triggerType,
    offsetMinutes: offsetMinutes,
    remindAt: remindAt ?? DateTime.now().add(const Duration(hours: 1)),
    status: status,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

void main() {
  group('scheduleReminder', () {
    test('schedules a pending, future reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder();

      await service.scheduleReminder(reminder);

      expect(gateway.scheduleCallCount, 1);
      final scheduled = gateway.scheduled[reminderNotificationId(reminder.id)];
      expect(scheduled, isNotNull);
      expect(scheduled!.title, reminder.title);
      expect(scheduled.remindAtUtc, reminder.remindAt);
      expect(scheduled.payload, contains(reminder.id));
    });

    test('does not schedule a past pending reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder(
        remindAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await service.scheduleReminder(reminder);

      expect(gateway.scheduleCallCount, 0);
    });

    test('does not schedule a cancelled reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder(status: ReminderStatus.cancelled);

      await service.scheduleReminder(reminder);

      expect(gateway.scheduleCallCount, 0);
    });

    test('does not schedule a triggered reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder(status: ReminderStatus.triggered);

      await service.scheduleReminder(reminder);

      expect(gateway.scheduleCallCount, 0);
    });

    test(
      'a denied permission silently skips scheduling instead of throwing',
      () async {
        final gateway = FakeNotificationPluginGateway(
          initialStatus: NotificationPermissionStatus.denied,
        );
        final service = LocalNotificationService(gateway: gateway);
        final reminder = _reminder();

        await expectLater(service.scheduleReminder(reminder), completes);

        expect(gateway.scheduleCallCount, 0);
      },
    );

    test('uses exact scheduling when the platform allows it', () async {
      final gateway = FakeNotificationPluginGateway(canScheduleExact: true);
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder();

      await service.scheduleReminder(reminder);

      final scheduled = gateway.scheduled[reminderNotificationId(reminder.id)];
      expect(scheduled!.useExactScheduling, isTrue);
    });

    test(
      'falls back to inexact scheduling when exact alarms are unavailable',
      () async {
        final gateway = FakeNotificationPluginGateway(canScheduleExact: false);
        final service = LocalNotificationService(gateway: gateway);
        final reminder = _reminder();

        await service.scheduleReminder(reminder);

        final scheduled =
            gateway.scheduled[reminderNotificationId(reminder.id)];
        expect(scheduled!.useExactScheduling, isFalse);
      },
    );
  });

  group('cancelReminder', () {
    test('cancels using the deterministic notification id', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      const reminderId = 'reminder-1';

      await service.cancelReminder(reminderId);

      expect(gateway.cancelCalls, [reminderNotificationId(reminderId)]);
    });
  });

  group('rescheduleReminder', () {
    test(
      'cancels the previous schedule and then schedules the new one',
      () async {
        final gateway = FakeNotificationPluginGateway();
        final service = LocalNotificationService(gateway: gateway);
        final reminder = _reminder();

        await service.rescheduleReminder(reminder);

        expect(gateway.cancelCalls, [reminderNotificationId(reminder.id)]);
        expect(gateway.scheduleCallCount, 1);
      },
    );

    test('cancelling before scheduling means a past reminder ends up '
        'cancelled, not scheduled', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final pastReminder = _reminder(
        remindAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await service.rescheduleReminder(pastReminder);

      expect(gateway.cancelCalls, [reminderNotificationId(pastReminder.id)]);
      expect(gateway.scheduleCallCount, 0);
    });
  });

  group('reconcilePendingReminders', () {
    test(
      'schedules a future pending reminder that was not yet scheduled',
      () async {
        final gateway = FakeNotificationPluginGateway();
        final service = LocalNotificationService(gateway: gateway);
        final reminder = _reminder();

        await service.reconcilePendingReminders([reminder]);

        expect(gateway.scheduleCallCount, 1);
        expect(
          gateway.scheduled[reminderNotificationId(reminder.id)],
          isNotNull,
        );
      },
    );

    test('skips a past pending reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder(
        remindAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await service.reconcilePendingReminders([reminder]);

      expect(gateway.scheduleCallCount, 0);
    });

    test('removes any local schedule for a cancelled reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder(status: ReminderStatus.cancelled);
      // Simulate a stale local schedule left over from before it was
      // cancelled.
      await gateway.scheduleAt(
        id: reminderNotificationId(reminder.id),
        title: reminder.title,
        body: 'Reminder',
        remindAtUtc: reminder.remindAt,
        payload: '{"reminderId":"${reminder.id}"}',
        useExactScheduling: false,
      );

      await service.reconcilePendingReminders([reminder]);

      expect(
        gateway.cancelCalls,
        contains(reminderNotificationId(reminder.id)),
      );
      expect(gateway.scheduled[reminderNotificationId(reminder.id)], isNull);
    });

    test('removes any local schedule for a triggered reminder', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final reminder = _reminder(status: ReminderStatus.triggered);
      await gateway.scheduleAt(
        id: reminderNotificationId(reminder.id),
        title: reminder.title,
        body: 'Reminder',
        remindAtUtc: reminder.remindAt,
        payload: '{"reminderId":"${reminder.id}"}',
        useExactScheduling: false,
      );

      await service.reconcilePendingReminders([reminder]);

      expect(
        gateway.cancelCalls,
        contains(reminderNotificationId(reminder.id)),
      );
    });

    test('cancels an orphaned local schedule for a reminder no longer in '
        'the loaded list (e.g. deleted while the app was closed)', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      const deletedReminderId = 'reminder-deleted';
      await gateway.scheduleAt(
        id: reminderNotificationId(deletedReminderId),
        title: 'Old reminder',
        body: 'Reminder',
        remindAtUtc: DateTime.now().add(const Duration(hours: 1)),
        payload: '{"reminderId":"$deletedReminderId"}',
        useExactScheduling: false,
      );

      await service.reconcilePendingReminders(const []);

      expect(
        gateway.cancelCalls,
        contains(reminderNotificationId(deletedReminderId)),
      );
    });

    test('never touches a notification with an unrecognized payload '
        '(owned by a different feature)', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      const foreignId = 999999;
      await gateway.scheduleAt(
        id: foreignId,
        title: 'Some other feature',
        body: '...',
        remindAtUtc: DateTime.now().add(const Duration(hours: 1)),
        payload: 'not-json-and-not-ours',
        useExactScheduling: false,
      );

      await service.reconcilePendingReminders(const []);

      expect(gateway.cancelCalls, isNot(contains(foreignId)));
      expect(gateway.scheduled[foreignId], isNotNull);
    });

    test('reconciles multiple reminders independently -- one failure does '
        'not stop the rest', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      final healthy = _reminder(id: 'reminder-healthy');
      final troubled = _reminder(id: 'reminder-troubled');

      // Pre-populate a stale schedule for `troubled` so its reconciliation
      // path calls cancel() (which is made to throw) before scheduling.
      await gateway.scheduleAt(
        id: reminderNotificationId(troubled.id),
        title: troubled.title,
        body: 'Reminder',
        remindAtUtc: troubled.remindAt,
        payload: '{"reminderId":"${troubled.id}"}',
        useExactScheduling: false,
      );
      gateway.throwOnCancelForId = reminderNotificationId(troubled.id);

      await expectLater(
        service.reconcilePendingReminders([healthy, troubled]),
        completes,
      );

      // `healthy` still got scheduled despite `troubled`'s cancel throwing.
      expect(gateway.scheduled[reminderNotificationId(healthy.id)], isNotNull);
    });
  });

  group('onNotificationTapped', () {
    test('emits the decoded payload when the gateway reports a tap', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      final future = service.onNotificationTapped.first;
      gateway.simulateTap('{"reminderId":"reminder-1","taskId":"task-1"}');

      final payload = await future;
      expect(payload.reminderId, 'reminder-1');
      expect(payload.taskId, 'task-1');
    });

    test('ignores an unrecognized tap payload', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);
      await service.initialize();

      final events = <dynamic>[];
      final subscription = service.onNotificationTapped.listen(events.add);

      gateway.simulateTap('not json');
      gateway.simulateTap('{"reminderId":"reminder-1"}');
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await subscription.cancel();
    });
  });

  group('consumeInitialLaunchPayload', () {
    test('a cold start from a valid reminder notification is captured during '
        'initialize() and returned once', () async {
      final gateway = FakeNotificationPluginGateway()
        ..launchPayload =
            '{"reminderId":"reminder-1","calendarEventId":"event-1"}';
      final service = LocalNotificationService(gateway: gateway);

      await service.initialize();
      final payload = service.consumeInitialLaunchPayload();

      expect(payload, isNotNull);
      expect(payload!.reminderId, 'reminder-1');
      expect(payload.calendarEventId, 'event-1');
    });

    test('a normal cold start (no launch payload) yields null', () async {
      final gateway = FakeNotificationPluginGateway();
      final service = LocalNotificationService(gateway: gateway);

      await service.initialize();

      expect(service.consumeInitialLaunchPayload(), isNull);
    });

    test(
      'a malformed or unrelated launch payload is ignored, not thrown',
      () async {
        final gateway = FakeNotificationPluginGateway()
          ..launchPayload = 'not json';
        final service = LocalNotificationService(gateway: gateway);

        await expectLater(service.initialize(), completes);

        expect(service.consumeInitialLaunchPayload(), isNull);
      },
    );

    test('a launch-details lookup failure does not prevent initialize() from '
        'completing', () async {
      final gateway = FakeNotificationPluginGateway()
        ..throwOnGetLaunchPayload = true;
      final service = LocalNotificationService(gateway: gateway);

      await expectLater(service.initialize(), completes);

      expect(service.consumeInitialLaunchPayload(), isNull);
    });

    test('is consumed only once -- a second call returns null', () async {
      final gateway = FakeNotificationPluginGateway()
        ..launchPayload = '{"reminderId":"reminder-1"}';
      final service = LocalNotificationService(gateway: gateway);

      await service.initialize();

      final first = service.consumeInitialLaunchPayload();
      final second = service.consumeInitialLaunchPayload();

      expect(first, isNotNull);
      expect(second, isNull);
    });
  });
}
