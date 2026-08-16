import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/reminders/create_reminder_input.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';

void main() {
  group('CreateReminderInput.validateTitle', () {
    test('rejects an empty title', () {
      expect(CreateReminderInput.validateTitle(''), isNotNull);
    });

    test('rejects a whitespace-only title', () {
      expect(CreateReminderInput.validateTitle('   '), isNotNull);
    });

    test('rejects a title over 200 characters', () {
      expect(CreateReminderInput.validateTitle('a' * 201), isNotNull);
    });

    test('accepts a title at exactly 200 characters', () {
      expect(CreateReminderInput.validateTitle('a' * 200), isNull);
    });

    test('accepts a valid title', () {
      expect(CreateReminderInput.validateTitle('Call insurance'), isNull);
    });
  });

  group('CreateReminderInput.toJson', () {
    test('serializes a standalone absolute reminder with a local DateTime '
        'converted to UTC ISO', () {
      // A local time with a fixed, non-zero UTC offset.
      final localRemindAt = DateTime.parse('2026-08-18T18:00:00.000+02:00');
      final input = CreateReminderInput(
        title: 'Call insurance',
        triggerType: ReminderTriggerType.absolute,
        remindAt: localRemindAt,
      );

      expect(input.toJson(), {
        'title': 'Call insurance',
        'triggerType': 'absolute',
        'remindAt': '2026-08-18T16:00:00.000Z',
      });
    });

    test('omits taskId, calendarEventId, and offsetMinutes when absent', () {
      final input = CreateReminderInput(
        title: 'Call insurance',
        triggerType: ReminderTriggerType.absolute,
        remindAt: DateTime.utc(2026, 8, 18, 18),
      );

      expect(input.toJson(), isNot(contains('taskId')));
      expect(input.toJson(), isNot(contains('calendarEventId')));
      expect(input.toJson(), isNot(contains('offsetMinutes')));
    });

    test('includes taskId for a task-linked absolute reminder', () {
      final input = CreateReminderInput(
        title: 'Finish report',
        taskId: 'task-1',
        triggerType: ReminderTriggerType.absolute,
        remindAt: DateTime.utc(2026, 8, 18, 9),
      );

      expect(input.toJson(), {
        'title': 'Finish report',
        'taskId': 'task-1',
        'triggerType': 'absolute',
        'remindAt': '2026-08-18T09:00:00.000Z',
      });
    });

    test('includes calendarEventId and offsetMinutes for a relative Calendar '
        'reminder', () {
      final input = CreateReminderInput(
        title: 'Team sync',
        calendarEventId: 'event-1',
        triggerType: ReminderTriggerType.relative,
        offsetMinutes: -15,
        remindAt: DateTime.utc(2026, 8, 20, 8, 45),
      );

      expect(input.toJson(), {
        'title': 'Team sync',
        'calendarEventId': 'event-1',
        'triggerType': 'relative',
        'offsetMinutes': -15,
        'remindAt': '2026-08-20T08:45:00.000Z',
      });
    });

    test('serializes a positive offset (after the event start)', () {
      final input = CreateReminderInput(
        title: 'Post-meeting notes',
        calendarEventId: 'event-1',
        triggerType: ReminderTriggerType.relative,
        offsetMinutes: 10,
        remindAt: DateTime.utc(2026, 8, 20, 9, 10),
      );

      expect(input.toJson()['offsetMinutes'], 10);
    });
  });
}
