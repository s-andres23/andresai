import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';

void main() {
  group('CalendarEvent.fromJson', () {
    test('parses a fully populated API response', () {
      final event = CalendarEvent.fromJson({
        'id': 'event-1',
        'userId': 'user-1',
        'title': 'Team sync',
        'description': 'Weekly sync with the team',
        'startAt': '2026-08-20T09:00:00.000Z',
        'endAt': '2026-08-20T09:30:00.000Z',
        'allDay': false,
        'location': 'Conference room A',
        'createdAt': '2026-08-13T00:00:00.000Z',
        'updatedAt': '2026-08-13T00:00:00.000Z',
      });

      expect(event.id, 'event-1');
      expect(event.userId, 'user-1');
      expect(event.title, 'Team sync');
      expect(event.description, 'Weekly sync with the team');
      expect(event.startAt, DateTime.parse('2026-08-20T09:00:00.000Z'));
      expect(event.endAt, DateTime.parse('2026-08-20T09:30:00.000Z'));
      expect(event.allDay, false);
      expect(event.location, 'Conference room A');
      expect(event.createdAt, DateTime.parse('2026-08-13T00:00:00.000Z'));
      expect(event.updatedAt, DateTime.parse('2026-08-13T00:00:00.000Z'));
    });

    test('parses an event with nullable fields absent', () {
      final event = CalendarEvent.fromJson({
        'id': 'event-2',
        'userId': 'user-1',
        'title': 'Focus block',
        'description': null,
        'startAt': '2026-08-21T00:00:00.000Z',
        'endAt': '2026-08-22T00:00:00.000Z',
        'allDay': true,
        'location': null,
        'createdAt': '2026-08-13T00:00:00.000Z',
        'updatedAt': '2026-08-13T00:00:00.000Z',
      });

      expect(event.description, isNull);
      expect(event.location, isNull);
      expect(event.allDay, true);
    });

    test('parses a timestamp using a numeric UTC offset instead of Z', () {
      // Postgres/PostgREST may render timestamps with a `+00:00` offset
      // instead of a `Z` suffix; DateTime.parse must handle both.
      final event = CalendarEvent.fromJson({
        'id': 'event-3',
        'userId': 'user-1',
        'title': 'Team sync',
        'description': null,
        'startAt': '2026-08-20T09:00:00+00:00',
        'endAt': '2026-08-20T09:30:00+00:00',
        'allDay': false,
        'location': null,
        'createdAt': '2026-08-13T00:00:00+00:00',
        'updatedAt': '2026-08-13T00:00:00+00:00',
      });

      expect(event.startAt, DateTime.parse('2026-08-20T09:00:00.000Z'));
      expect(event.endAt, DateTime.parse('2026-08-20T09:30:00.000Z'));
    });
  });
}
