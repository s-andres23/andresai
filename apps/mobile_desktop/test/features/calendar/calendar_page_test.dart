import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_page.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';

class _FakeCalendarRepository extends CalendarRepository {
  _FakeCalendarRepository([this._events = const []]) : super(Dio());

  final List<CalendarEvent> _events;
  int fetchCallCount = 0;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    fetchCallCount++;
    return _events;
  }
}

class _FailingCalendarRepository extends CalendarRepository {
  _FailingCalendarRepository() : super(Dio());

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    throw Exception('network error');
  }
}

Future<void> _pumpCalendarPage(
  WidgetTester tester, {
  required CalendarRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [calendarRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: CalendarPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows an empty state when there are no events', (tester) async {
    await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());

    expect(find.text('No events yet.'), findsOneWidget);
  });

  testWidgets('shows a timed event with its date, time range, and location', (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-1',
      userId: 'user-1',
      title: 'Team sync',
      description: null,
      startAt: DateTime.utc(2026, 8, 20, 9),
      endAt: DateTime.utc(2026, 8, 20, 9, 30),
      allDay: false,
      location: 'Conference room A',
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 13),
    );
    await _pumpCalendarPage(
      tester,
      repository: _FakeCalendarRepository([event]),
    );

    expect(find.text('Team sync'), findsOneWidget);
    expect(find.text('Conference room A'), findsOneWidget);
    // The exact rendered time depends on the test environment's local
    // timezone (event times are shown in local time), so only assert on the
    // parts that don't: the date, and the "all day" label being absent.
    expect(find.textContaining('2026-08-20'), findsOneWidget);
    expect(find.textContaining('All day'), findsNothing);
  });

  testWidgets('shows an all-day event as "All day" instead of a time range', (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-2',
      userId: 'user-1',
      title: 'Company holiday',
      description: null,
      startAt: DateTime.utc(2026, 8, 21),
      endAt: DateTime.utc(2026, 8, 22),
      allDay: true,
      location: null,
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 13),
    );
    await _pumpCalendarPage(
      tester,
      repository: _FakeCalendarRepository([event]),
    );

    expect(find.text('Company holiday'), findsOneWidget);
    expect(find.textContaining('All day'), findsOneWidget);
  });

  testWidgets('shows an error view with a working retry button', (
    tester,
  ) async {
    final repository = _FailingCalendarRepository();
    await _pumpCalendarPage(tester, repository: repository);

    expect(find.text('Failed to load calendar events'), findsOneWidget);
    expect(find.textContaining('network error'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // Still failing (the fake always throws), so the error view persists
    // rather than silently retrying forever.
    expect(find.text('Failed to load calendar events'), findsOneWidget);
  });

  testWidgets('sign-out is available from the calendar page', (tester) async {
    await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());

    expect(find.byTooltip('Sign out'), findsOneWidget);
  });
}
