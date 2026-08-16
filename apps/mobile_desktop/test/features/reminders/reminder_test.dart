import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';

void main() {
  group('Reminder.fromJson', () {
    test('parses an absolute reminder', () {
      final reminder = Reminder.fromJson({
        'id': 'reminder-1',
        'userId': 'user-1',
        'taskId': null,
        'calendarEventId': null,
        'title': 'Call insurance',
        'triggerType': 'absolute',
        'offsetMinutes': null,
        'remindAt': '2026-08-18T18:00:00.000Z',
        'status': 'pending',
        'createdAt': '2026-08-14T00:00:00.000Z',
        'updatedAt': '2026-08-14T00:00:00.000Z',
      });

      expect(reminder.id, 'reminder-1');
      expect(reminder.userId, 'user-1');
      expect(reminder.taskId, isNull);
      expect(reminder.calendarEventId, isNull);
      expect(reminder.title, 'Call insurance');
      expect(reminder.triggerType, ReminderTriggerType.absolute);
      expect(reminder.offsetMinutes, isNull);
      expect(reminder.remindAt, DateTime.parse('2026-08-18T18:00:00.000Z'));
      expect(reminder.status, ReminderStatus.pending);
      expect(reminder.createdAt, DateTime.parse('2026-08-14T00:00:00.000Z'));
      expect(reminder.updatedAt, DateTime.parse('2026-08-14T00:00:00.000Z'));
    });

    test('parses a relative Calendar reminder', () {
      final reminder = Reminder.fromJson({
        'id': 'reminder-2',
        'userId': 'user-1',
        'taskId': null,
        'calendarEventId': 'event-1',
        'title': 'Team sync',
        'triggerType': 'relative',
        'offsetMinutes': -15,
        'remindAt': '2026-08-20T08:45:00.000Z',
        'status': 'pending',
        'createdAt': '2026-08-14T00:00:00.000Z',
        'updatedAt': '2026-08-14T00:00:00.000Z',
      });

      expect(reminder.calendarEventId, 'event-1');
      expect(reminder.triggerType, ReminderTriggerType.relative);
      expect(reminder.offsetMinutes, -15);
    });

    test('parses a task-linked absolute reminder', () {
      final reminder = Reminder.fromJson({
        'id': 'reminder-3',
        'userId': 'user-1',
        'taskId': 'task-1',
        'calendarEventId': null,
        'title': 'Finish report',
        'triggerType': 'absolute',
        'offsetMinutes': null,
        'remindAt': '2026-08-18T09:00:00.000Z',
        'status': 'pending',
        'createdAt': '2026-08-14T00:00:00.000Z',
        'updatedAt': '2026-08-14T00:00:00.000Z',
      });

      expect(reminder.taskId, 'task-1');
      expect(reminder.calendarEventId, isNull);
    });

    test('parses each status', () {
      for (final status in ['pending', 'triggered', 'cancelled']) {
        final reminder = Reminder.fromJson({
          'id': 'reminder-1',
          'userId': 'user-1',
          'taskId': null,
          'calendarEventId': null,
          'title': 'Call insurance',
          'triggerType': 'absolute',
          'offsetMinutes': null,
          'remindAt': '2026-08-18T18:00:00.000Z',
          'status': status,
          'createdAt': '2026-08-14T00:00:00.000Z',
          'updatedAt': '2026-08-14T00:00:00.000Z',
        });

        expect(reminder.status, ReminderStatus.values.byName(status));
      }
    });

    test('parses a timestamp using a numeric UTC offset instead of Z', () {
      // Postgres/PostgREST may render timestamps with a `+00:00` offset
      // instead of a `Z` suffix; DateTime.parse must handle both.
      final reminder = Reminder.fromJson({
        'id': 'reminder-1',
        'userId': 'user-1',
        'taskId': null,
        'calendarEventId': null,
        'title': 'Call insurance',
        'triggerType': 'absolute',
        'offsetMinutes': null,
        'remindAt': '2026-08-18T18:00:00+00:00',
        'status': 'pending',
        'createdAt': '2026-08-14T00:00:00+00:00',
        'updatedAt': '2026-08-14T00:00:00+00:00',
      });

      expect(reminder.remindAt, DateTime.parse('2026-08-18T18:00:00.000Z'));
    });
  });
}
