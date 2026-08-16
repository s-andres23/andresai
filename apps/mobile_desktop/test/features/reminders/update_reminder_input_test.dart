import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/reminders/update_reminder_input.dart';

void main() {
  group('UpdateReminderInput.toJson', () {
    test('sends only title when neither offsetMinutes nor remindAt change', () {
      const input = UpdateReminderInput(title: 'Call insurance (renamed)');

      expect(input.toJson(), {'title': 'Call insurance (renamed)'});
    });

    test('includes remindAt converted to UTC ISO when editing an absolute '
        'reminder', () {
      final input = UpdateReminderInput(
        title: 'Call insurance',
        remindAt: DateTime.parse('2026-08-19T10:00:00.000+02:00'),
      );

      expect(input.toJson(), {
        'title': 'Call insurance',
        'remindAt': '2026-08-19T08:00:00.000Z',
      });
    });

    test('includes offsetMinutes without remindAt when editing a relative '
        'reminder', () {
      const input = UpdateReminderInput(title: 'Team sync', offsetMinutes: -60);

      expect(input.toJson(), {'title': 'Team sync', 'offsetMinutes': -60});
    });
  });
}
