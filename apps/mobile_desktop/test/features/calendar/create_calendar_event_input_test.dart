import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/create_calendar_event_input.dart';

void main() {
  group('CreateCalendarEventInput.validateTitle', () {
    test('rejects an empty title', () {
      expect(CreateCalendarEventInput.validateTitle(''), isNotNull);
    });

    test('rejects a whitespace-only title', () {
      expect(CreateCalendarEventInput.validateTitle('   '), isNotNull);
    });

    test('rejects a title over 200 characters', () {
      expect(CreateCalendarEventInput.validateTitle('a' * 201), isNotNull);
    });

    test('accepts a title at exactly 200 characters', () {
      expect(CreateCalendarEventInput.validateTitle('a' * 200), isNull);
    });

    test('accepts a valid title', () {
      expect(CreateCalendarEventInput.validateTitle('Team sync'), isNull);
    });
  });

  group('CreateCalendarEventInput.validateDescription', () {
    test('accepts an empty description', () {
      expect(CreateCalendarEventInput.validateDescription(''), isNull);
    });

    test('rejects a description over 2000 characters', () {
      expect(
        CreateCalendarEventInput.validateDescription('a' * 2001),
        isNotNull,
      );
    });

    test('accepts a description at exactly 2000 characters', () {
      expect(CreateCalendarEventInput.validateDescription('a' * 2000), isNull);
    });
  });

  group('CreateCalendarEventInput.validateLocation', () {
    test('accepts an empty location', () {
      expect(CreateCalendarEventInput.validateLocation(''), isNull);
    });

    test('rejects a location over 200 characters', () {
      expect(CreateCalendarEventInput.validateLocation('a' * 201), isNotNull);
    });

    test('accepts a location at exactly 200 characters', () {
      expect(CreateCalendarEventInput.validateLocation('a' * 200), isNull);
    });
  });

  group('CreateCalendarEventInput.validateInterval', () {
    test('rejects an endAt before startAt', () {
      final startAt = DateTime.utc(2026, 8, 20, 9);
      final endAt = DateTime.utc(2026, 8, 20, 8);
      expect(
        CreateCalendarEventInput.validateInterval(startAt, endAt),
        isNotNull,
      );
    });

    test('accepts an endAt equal to startAt', () {
      final startAt = DateTime.utc(2026, 8, 20, 9);
      expect(
        CreateCalendarEventInput.validateInterval(startAt, startAt),
        isNull,
      );
    });

    test('accepts an endAt after startAt', () {
      final startAt = DateTime.utc(2026, 8, 20, 9);
      final endAt = DateTime.utc(2026, 8, 20, 9, 30);
      expect(CreateCalendarEventInput.validateInterval(startAt, endAt), isNull);
    });
  });

  group('CreateCalendarEventInput.toJson', () {
    test('includes only the required fields plus allDay when optional '
        'fields are absent', () {
      final input = CreateCalendarEventInput(
        title: 'Team sync',
        startAt: DateTime.utc(2026, 8, 20, 9),
        endAt: DateTime.utc(2026, 8, 20, 9, 30),
      );

      expect(input.toJson(), {
        'title': 'Team sync',
        'startAt': '2026-08-20T09:00:00.000Z',
        'endAt': '2026-08-20T09:30:00.000Z',
        'allDay': false,
      });
    });

    test('includes description, allDay, and location when present', () {
      final input = CreateCalendarEventInput(
        title: 'Team sync',
        description: 'Weekly sync with the team',
        startAt: DateTime.utc(2026, 8, 20, 9),
        endAt: DateTime.utc(2026, 8, 20, 9, 30),
        allDay: true,
        location: 'Conference room A',
      );

      expect(input.toJson(), {
        'title': 'Team sync',
        'description': 'Weekly sync with the team',
        'startAt': '2026-08-20T09:00:00.000Z',
        'endAt': '2026-08-20T09:30:00.000Z',
        'allDay': true,
        'location': 'Conference room A',
      });
    });

    test('sends timestamps converted to UTC regardless of input timezone', () {
      // A local time with a fixed, non-zero UTC offset.
      final localStart = DateTime.parse('2026-08-20T09:00:00.000+02:00');
      final localEnd = DateTime.parse('2026-08-20T10:00:00.000+02:00');
      final input = CreateCalendarEventInput(
        title: 'Team sync',
        startAt: localStart,
        endAt: localEnd,
      );

      expect(input.toJson()['startAt'], '2026-08-20T07:00:00.000Z');
      expect(input.toJson()['endAt'], '2026-08-20T08:00:00.000Z');
    });
  });
}
