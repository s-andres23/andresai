import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/notification_payload.dart';

void main() {
  group('NotificationPayload', () {
    test('round-trips reminderId only', () {
      const payload = NotificationPayload(reminderId: 'reminder-1');

      final decoded = NotificationPayload.decode(payload.encode());

      expect(decoded!.reminderId, 'reminder-1');
      expect(decoded.taskId, isNull);
      expect(decoded.calendarEventId, isNull);
    });

    test('round-trips a calendar-linked reminder', () {
      const payload = NotificationPayload(
        reminderId: 'reminder-1',
        calendarEventId: 'event-1',
      );

      final decoded = NotificationPayload.decode(payload.encode());

      expect(decoded!.calendarEventId, 'event-1');
      expect(decoded.taskId, isNull);
    });

    test('round-trips a task-linked reminder', () {
      const payload = NotificationPayload(
        reminderId: 'reminder-1',
        taskId: 'task-1',
      );

      final decoded = NotificationPayload.decode(payload.encode());

      expect(decoded!.taskId, 'task-1');
    });

    test('decode returns null for null, empty, or malformed input', () {
      expect(NotificationPayload.decode(null), isNull);
      expect(NotificationPayload.decode(''), isNull);
      expect(NotificationPayload.decode('not json'), isNull);
      expect(NotificationPayload.decode('{"no reminderId": true}'), isNull);
      expect(NotificationPayload.decode('[]'), isNull);
    });
  });
}
