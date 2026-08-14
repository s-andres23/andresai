import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_date_format.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_page.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/calendar/create_calendar_event_input.dart';

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

/// A repository whose `createEvent` succeeds, returning [eventToCreate] and
/// recording the input it was called with.
class _CreatingCalendarRepository extends CalendarRepository {
  _CreatingCalendarRepository(this._events, this.eventToCreate) : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent eventToCreate;
  CreateCalendarEventInput? lastInput;
  int createCallCount = 0;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async {
    createCallCount++;
    lastInput = input;
    return eventToCreate;
  }
}

class _FailingCreateCalendarRepository extends CalendarRepository {
  _FailingCreateCalendarRepository([this._events = const []]) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async {
    throw Exception('create failed');
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

Future<void> _openCreateEventSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add event'));
  await tester.pumpAndSettle();
}

/// Reads the label of the Nth date/time picker [TextButton] in the
/// create-event sheet. With all-day off, the order is: start date (0),
/// start time (1), end date (2), end time (3).
String _pickerButtonLabel(WidgetTester tester, int index) {
  final button = find.byType(TextButton).at(index);
  final label = find.descendant(of: button, matching: find.byType(Text));
  return tester.widget<Text>(label).data!;
}

/// Opens the date picker for the button at [buttonIndex], switches it to
/// text-input mode, types [date], and confirms -- driving the real
/// `showDatePicker` UI rather than stubbing it out.
Future<void> _pickDateViaTextInput(
  WidgetTester tester, {
  required int buttonIndex,
  required DateTime date,
}) async {
  await tester.tap(find.byType(TextButton).at(buttonIndex));
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byTooltip('Switch to input'),
    ),
  );
  await tester.pumpAndSettle();

  final dateText =
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year}';
  await tester.enterText(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    ),
    dateText,
  );
  await tester.tap(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text('OK'),
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

  testWidgets('create-event sheet shows the expected fields', (tester) async {
    await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
    await _openCreateEventSheet(tester);

    expect(find.text('New event'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Description (optional)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SwitchListTile, 'All day'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Location (optional)'),
      findsOneWidget,
    );
    expect(find.text('Create event'), findsOneWidget);
  });

  testWidgets('submitting an empty title shows a validation error', (
    tester,
  ) async {
    final repository = _CreatingCalendarRepository(const [], _sampleEvent);
    await _pumpCalendarPage(tester, repository: repository);
    await _openCreateEventSheet(tester);

    await tester.tap(find.text('Create event'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(repository.createCallCount, 0);
    // The sheet stays open so the user can fix the error.
    expect(find.text('New event'), findsOneWidget);
  });

  testWidgets('creating an event closes the sheet and shows it in the list', (
    tester,
  ) async {
    final repository = _CreatingCalendarRepository(const [], _sampleEvent);
    await _pumpCalendarPage(tester, repository: repository);
    await _openCreateEventSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Team sync',
    );
    await tester.tap(find.text('Create event'));
    await tester.pumpAndSettle();

    expect(repository.createCallCount, 1);
    expect(find.text('New event'), findsNothing);
    expect(find.text(_sampleEvent.title), findsOneWidget);
  });

  testWidgets(
    'a failed create shows an inline error and keeps the sheet open',
    (tester) async {
      await _pumpCalendarPage(
        tester,
        repository: _FailingCreateCalendarRepository(),
      );
      await _openCreateEventSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Team sync',
      );
      await tester.tap(find.text('Create event'));
      await tester.pumpAndSettle();

      expect(find.text('New event'), findsOneWidget);
      expect(find.textContaining('create failed'), findsOneWidget);
    },
  );

  testWidgets(
    'toggling all day hides the time pickers and sends full-day bounds',
    (tester) async {
      final repository = _CreatingCalendarRepository(const [], _sampleEvent);
      await _pumpCalendarPage(tester, repository: repository);
      await _openCreateEventSheet(tester);

      // Two time buttons are shown (start + end) while all-day is off.
      expect(find.byType(TextButton), findsNWidgets(4));

      await tester.tap(find.widgetWithText(SwitchListTile, 'All day'));
      await tester.pumpAndSettle();

      // Only the two date buttons remain once all-day is on.
      expect(find.byType(TextButton), findsNWidgets(2));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Company holiday',
      );
      await tester.tap(find.text('Create event'));
      await tester.pumpAndSettle();

      final sentInput = repository.lastInput!;
      expect(sentInput.allDay, isTrue);
      expect(sentInput.startAt.hour, 0);
      expect(sentInput.startAt.minute, 0);
      expect(
        sentInput.endAt.difference(sentInput.startAt),
        const Duration(days: 1),
      );
    },
  );

  testWidgets(
    'create-event sheet lays out without overflow in a small windowed '
    'desktop size',
    (tester) async {
      tester.view.physicalSize = const Size(400, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
      await _openCreateEventSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Create event'), findsOneWidget);
    },
  );

  testWidgets(
    'create-event sheet remains usable when a software keyboard is open',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      // Simulates a software keyboard covering roughly half the screen.
      tester.view.viewInsets = const FakeViewPadding(bottom: 420);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
      await _openCreateEventSheet(tester);

      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Create event'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create event'), findsOneWidget);
    },
  );

  testWidgets('create-event sheet caps its width on a large desktop window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
    await _openCreateEventSheet(tester);

    final formWidth = tester.getSize(find.byType(Form)).width;

    expect(formWidth, lessThanOrEqualTo(480));
  });

  testWidgets('initial end is start plus 1 hour', (tester) async {
    await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
    await _openCreateEventSheet(tester);

    final startDate = _pickerButtonLabel(tester, 0);
    final startTime = _pickerButtonLabel(tester, 1);
    final endDate = _pickerButtonLabel(tester, 2);
    final endTime = _pickerButtonLabel(tester, 3);

    // Under normal test conditions (not within an hour of midnight), the
    // default start/end fall on the same day.
    expect(endDate, startDate);

    final startMinutes = _minutesSinceMidnight(startTime);
    final endMinutes = _minutesSinceMidnight(endTime);
    expect((endMinutes - startMinutes) % (24 * 60), 60);
  });

  testWidgets(
    'changing the start date preserves duration and moves end to the same '
    'date',
    (tester) async {
      await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
      await _openCreateEventSheet(tester);

      final initialStartTime = _pickerButtonLabel(tester, 1);
      final initialEndTime = _pickerButtonLabel(tester, 3);

      final future = DateTime.now().add(const Duration(days: 4));
      await _pickDateViaTextInput(tester, buttonIndex: 0, date: future);

      final expectedDate = formatCalendarDate(future);
      expect(_pickerButtonLabel(tester, 0), expectedDate);
      // End's date follows start to the same future date...
      expect(_pickerButtonLabel(tester, 2), expectedDate);
      // ...while the time-of-day for both fields is unchanged, since only
      // the date (not the time) was edited.
      expect(_pickerButtonLabel(tester, 1), initialStartTime);
      expect(_pickerButtonLabel(tester, 3), initialEndTime);
    },
  );

  testWidgets(
    'end remains manually editable after an automatic adjustment from a '
    'start change',
    (tester) async {
      await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
      await _openCreateEventSheet(tester);

      // First, change start's date; end auto-adjusts to preserve duration.
      final newStart = DateTime.now().add(const Duration(days: 4));
      await _pickDateViaTextInput(tester, buttonIndex: 0, date: newStart);

      // Now manually edit end's date to something else entirely.
      final customEndDate = newStart.add(const Duration(days: 2));
      await _pickDateViaTextInput(tester, buttonIndex: 2, date: customEndDate);

      // The manual edit sticks...
      expect(_pickerButtonLabel(tester, 2), formatCalendarDate(customEndDate));
      // ...and does not reverse-sync onto start.
      expect(_pickerButtonLabel(tester, 0), formatCalendarDate(newStart));
    },
  );

  testWidgets(
    'falls back to a 1-hour end when the previous interval was invalid',
    (tester) async {
      await _pumpCalendarPage(tester, repository: _FakeCalendarRepository());
      await _openCreateEventSheet(tester);

      // Manually set end to a date before the current start, producing an
      // invalid (negative) interval.
      final past = DateTime.now().subtract(const Duration(days: 5));
      await _pickDateViaTextInput(tester, buttonIndex: 2, date: past);
      expect(_pickerButtonLabel(tester, 2), formatCalendarDate(past));

      // Changing start again must fall back to start + 1 hour rather than
      // preserving the broken negative gap.
      final newStart = DateTime.now().add(const Duration(days: 2));
      await _pickDateViaTextInput(tester, buttonIndex: 0, date: newStart);

      final expectedDate = formatCalendarDate(newStart);
      expect(_pickerButtonLabel(tester, 0), expectedDate);
      expect(_pickerButtonLabel(tester, 2), expectedDate);

      final startMinutes = _minutesSinceMidnight(_pickerButtonLabel(tester, 1));
      final endMinutes = _minutesSinceMidnight(_pickerButtonLabel(tester, 3));
      expect((endMinutes - startMinutes) % (24 * 60), 60);
    },
  );

  group('computeEndAfterStartChange', () {
    test('preserves the previous duration relative to the new start '
        '(bug report example)', () {
      final result = computeEndAfterStartChange(
        previousStart: DateTime(2026, 8, 14, 20),
        previousEnd: DateTime(2026, 8, 14, 21),
        newStart: DateTime(2026, 8, 18, 16, 30),
      );

      expect(result, DateTime(2026, 8, 18, 17, 30));
    });

    test('preserves an arbitrary non-1-hour duration', () {
      final result = computeEndAfterStartChange(
        previousStart: DateTime(2026, 8, 14, 9),
        previousEnd: DateTime(2026, 8, 14, 11, 15),
        newStart: DateTime(2026, 8, 20, 8),
      );

      expect(result, DateTime(2026, 8, 20, 10, 15));
    });

    test('falls back to 1 hour when the previous interval is negative', () {
      final result = computeEndAfterStartChange(
        previousStart: DateTime(2026, 8, 14, 20),
        previousEnd: DateTime(2026, 8, 14, 19),
        newStart: DateTime(2026, 8, 18, 16, 30),
      );

      expect(result, DateTime(2026, 8, 18, 17, 30));
    });

    test('falls back to 1 hour when the previous interval is zero', () {
      final sameInstant = DateTime(2026, 8, 14, 20);

      final result = computeEndAfterStartChange(
        previousStart: sameInstant,
        previousEnd: sameInstant,
        newStart: DateTime(2026, 8, 18, 16, 30),
      );

      expect(result, DateTime(2026, 8, 18, 17, 30));
    });
  });
}

/// Parses an `HH:mm` label (as produced by [formatCalendarTime]) into
/// minutes since midnight.
int _minutesSinceMidnight(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

final _sampleEvent = CalendarEvent(
  id: 'event-created',
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
