import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_date_format.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_page.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/calendar/create_calendar_event_input.dart';
import 'package:mobile_desktop/features/calendar/update_calendar_event_input.dart';

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

/// A repository whose `updateEvent` succeeds, returning [eventToReturn] and
/// recording the event ID/input it was called with.
class _UpdatingCalendarRepository extends CalendarRepository {
  _UpdatingCalendarRepository(this._events, this.eventToReturn) : super(Dio());

  final List<CalendarEvent> _events;
  final CalendarEvent eventToReturn;
  String? lastEventId;
  UpdateCalendarEventInput? lastInput;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async {
    lastEventId = eventId;
    lastInput = input;
    return eventToReturn;
  }
}

class _FailingUpdateCalendarRepository extends CalendarRepository {
  _FailingUpdateCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async {
    throw Exception('update failed');
  }
}

/// A repository whose `deleteEvent` succeeds, recording every call.
class _DeletingCalendarRepository extends CalendarRepository {
  _DeletingCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;
  int deleteCallCount = 0;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<void> deleteEvent(String eventId) async {
    deleteCallCount++;
  }
}

class _FailingDeleteCalendarRepository extends CalendarRepository {
  _FailingDeleteCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<void> deleteEvent(String eventId) async {
    throw Exception('delete failed');
  }
}

/// A repository whose `deleteEvent` doesn't resolve until [deleteCompleter]
/// is completed, so a test can observe the deleting tile's loading state
/// before letting the event actually disappear from the list.
class _PendingDeleteCalendarRepository extends CalendarRepository {
  _PendingDeleteCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;
  final deleteCompleter = Completer<void>();

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<void> deleteEvent(String eventId) => deleteCompleter.future;
}

/// A repository whose `deleteEvent` doesn't resolve until [deleteCompleter]
/// is completed, and whose `createEvent` immediately returns
/// [eventToCreate] -- so a test can keep one event mid-mutation (deleting)
/// while creating (and prepending) a different event.
class _PendingDeleteAndCreateCalendarRepository extends CalendarRepository {
  _PendingDeleteAndCreateCalendarRepository(this._events) : super(Dio());

  final List<CalendarEvent> _events;
  final deleteCompleter = Completer<void>();
  CalendarEvent? eventToCreate;

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => _events;

  @override
  Future<void> deleteEvent(String eventId) => deleteCompleter.future;

  @override
  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async =>
      eventToCreate!;
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

Future<void> _openEventMenu(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.byTooltip('Event actions').at(index));
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

/// Advances frames in small steps without waiting for animations to finish.
///
/// Use this instead of `pumpAndSettle` when another widget in the tree (e.g.
/// a tile's indeterminate loading spinner) is animating indefinitely, which
/// would otherwise make `pumpAndSettle` hang forever.
Future<void> _pumpFrames(
  WidgetTester tester, [
  Duration total = const Duration(milliseconds: 500),
]) async {
  await tester.pump();
  const step = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
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

  testWidgets('edit sheet is prefilled with the current event values', (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-1',
      userId: 'user-1',
      title: 'Team sync',
      description: 'Weekly sync',
      startAt: DateTime(2026, 8, 20, 9),
      endAt: DateTime(2026, 8, 20, 9, 30),
      allDay: false,
      location: 'Conference room A',
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    await _pumpCalendarPage(
      tester,
      repository: _FakeCalendarRepository([event]),
    );

    await _openEventMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit event'), findsOneWidget);
    final titleField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Title'),
    );
    expect(titleField.controller!.text, 'Team sync');
    final descriptionField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Description (optional)'),
    );
    expect(descriptionField.controller!.text, 'Weekly sync');
    final locationField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Location (optional)'),
    );
    expect(locationField.controller!.text, 'Conference room A');
    expect(_pickerButtonLabel(tester, 0), formatCalendarDate(event.startAt));
    expect(_pickerButtonLabel(tester, 1), formatCalendarTime(event.startAt));
    expect(_pickerButtonLabel(tester, 2), formatCalendarDate(event.endAt));
    expect(_pickerButtonLabel(tester, 3), formatCalendarTime(event.endAt));
  });

  testWidgets(
    "edit sheet prefills an all-day event's end as the inclusive last day",
    (tester) async {
      // A 3-day all-day event (Aug 10-12 inclusive), stored with an
      // exclusive end of Aug 13 (midnight after the last day).
      final event = CalendarEvent(
        id: 'event-1',
        userId: 'user-1',
        title: 'Conference',
        description: null,
        startAt: DateTime(2026, 8, 10),
        endAt: DateTime(2026, 8, 13),
        allDay: true,
        location: null,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );
      await _pumpCalendarPage(
        tester,
        repository: _FakeCalendarRepository([event]),
      );

      await _openEventMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final allDaySwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'All day'),
      );
      expect(allDaySwitch.value, isTrue);
      // With all-day on, only the two date buttons are shown (no time).
      expect(_pickerButtonLabel(tester, 0), formatCalendarDate(event.startAt));
      expect(
        _pickerButtonLabel(tester, 1),
        formatCalendarDate(DateTime(2026, 8, 12)),
      );
    },
  );

  testWidgets("editing the start date preserves the event's duration", (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-1',
      userId: 'user-1',
      title: 'Team sync',
      description: null,
      startAt: DateTime(2026, 8, 14, 20),
      endAt: DateTime(2026, 8, 14, 21), // 1-hour event
      allDay: false,
      location: null,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    final repository = _UpdatingCalendarRepository([event], event);
    await _pumpCalendarPage(tester, repository: repository);

    await _openEventMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await _pickDateViaTextInput(
      tester,
      buttonIndex: 0,
      date: DateTime(2026, 8, 18),
    );

    // End's date follows, preserving the original 1-hour duration...
    expect(_pickerButtonLabel(tester, 2), '2026-08-18');
    // ...while its time-of-day is unchanged, since only the date (not the
    // time) was edited.
    expect(_pickerButtonLabel(tester, 3), '21:00');

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repository.lastInput!.startAt, DateTime(2026, 8, 18, 20));
    expect(repository.lastInput!.endAt, DateTime(2026, 8, 18, 21));
  });

  testWidgets(
    'editing an event submits the update and reflects it in the list',
    (tester) async {
      final event = CalendarEvent(
        id: 'event-1',
        userId: 'user-1',
        title: 'Team sync',
        description: null,
        startAt: DateTime(2026, 8, 20, 9),
        endAt: DateTime(2026, 8, 20, 9, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final updatedEvent = CalendarEvent(
        id: event.id,
        userId: event.userId,
        title: 'Team sync (renamed)',
        description: event.description,
        startAt: event.startAt,
        endAt: event.endAt,
        allDay: event.allDay,
        location: event.location,
        createdAt: event.createdAt,
        updatedAt: DateTime(2026, 8, 14),
      );
      final repository = _UpdatingCalendarRepository([event], updatedEvent);
      await _pumpCalendarPage(tester, repository: repository);

      await _openEventMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Team sync (renamed)',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(repository.lastEventId, event.id);
      expect(find.text('Edit event'), findsNothing);
      expect(find.text('Team sync (renamed)'), findsOneWidget);
    },
  );

  testWidgets('a failed edit shows an inline error and keeps the sheet open', (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-1',
      userId: 'user-1',
      title: 'Team sync',
      description: null,
      startAt: DateTime(2026, 8, 20, 9),
      endAt: DateTime(2026, 8, 20, 9, 30),
      allDay: false,
      location: null,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    await _pumpCalendarPage(
      tester,
      repository: _FailingUpdateCalendarRepository([event]),
    );

    await _openEventMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Edit event'), findsOneWidget);
    expect(find.textContaining('update failed'), findsOneWidget);
  });

  testWidgets(
    'edit sheet lays out without overflow in a small windowed desktop size',
    (tester) async {
      tester.view.physicalSize = const Size(400, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final event = CalendarEvent(
        id: 'event-1',
        userId: 'user-1',
        title: 'Team sync',
        description: null,
        startAt: DateTime(2026, 8, 20, 9),
        endAt: DateTime(2026, 8, 20, 9, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      await _pumpCalendarPage(
        tester,
        repository: _FakeCalendarRepository([event]),
      );
      await _openEventMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    },
  );

  testWidgets('canceling the delete confirmation keeps the event', (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-1',
      userId: 'user-1',
      title: 'Team sync',
      description: null,
      startAt: DateTime(2026, 8, 20, 9),
      endAt: DateTime(2026, 8, 20, 9, 30),
      allDay: false,
      location: null,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    final repository = _DeletingCalendarRepository([event]);
    await _pumpCalendarPage(tester, repository: repository);

    await _openEventMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete event?'), findsOneWidget);
    expect(find.textContaining(event.title), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 0);
    expect(find.text(event.title), findsOneWidget);
  });

  testWidgets('confirming delete removes the event from the list', (
    tester,
  ) async {
    final event = CalendarEvent(
      id: 'event-1',
      userId: 'user-1',
      title: 'Team sync',
      description: null,
      startAt: DateTime(2026, 8, 20, 9),
      endAt: DateTime(2026, 8, 20, 9, 30),
      allDay: false,
      location: null,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    final repository = _DeletingCalendarRepository([event]);
    await _pumpCalendarPage(tester, repository: repository);

    await _openEventMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 1);
    expect(find.text(event.title), findsNothing);
    expect(find.text('No events yet.'), findsOneWidget);
  });

  testWidgets(
    'a failed delete shows an error and keeps the event in the list',
    (tester) async {
      final event = CalendarEvent(
        id: 'event-1',
        userId: 'user-1',
        title: 'Team sync',
        description: null,
        startAt: DateTime(2026, 8, 20, 9),
        endAt: DateTime(2026, 8, 20, 9, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      await _pumpCalendarPage(
        tester,
        repository: _FailingDeleteCalendarRepository([event]),
      );

      await _openEventMenu(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to delete event'), findsOneWidget);
      expect(find.text(event.title), findsOneWidget);
    },
  );

  testWidgets('deleting an event while its tile is loading does not leave a '
      'different remaining event stuck loading', (tester) async {
    final eventA = CalendarEvent(
      id: 'event-a',
      userId: 'user-1',
      title: 'Event A',
      description: null,
      startAt: DateTime(2026, 8, 20, 8),
      endAt: DateTime(2026, 8, 20, 8, 30),
      allDay: false,
      location: null,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    final eventB = CalendarEvent(
      id: 'event-b',
      userId: 'user-1',
      title: 'Event B',
      description: null,
      startAt: DateTime(2026, 8, 20, 9),
      endAt: DateTime(2026, 8, 20, 9, 30),
      allDay: false,
      location: null,
      createdAt: DateTime(2026, 8, 13),
      updatedAt: DateTime(2026, 8, 13),
    );
    final repository = _PendingDeleteCalendarRepository([eventA, eventB]);
    await _pumpCalendarPage(tester, repository: repository);

    // Start deleting eventA (index 0): its tile enters the loading state
    // while the request is in flight.
    await tester.tap(find.byTooltip('Event actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.deleteCompleter.complete();
    await tester.pumpAndSettle();

    // eventA is gone. eventB, which shifted into eventA's old list
    // index, must not have inherited eventA's loading state.
    expect(find.text(eventA.title), findsNothing);
    expect(find.text(eventB.title), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byTooltip('Event actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets(
    'removing a middle event does not transfer tile state to the next '
    'event',
    (tester) async {
      final eventA = CalendarEvent(
        id: 'event-a',
        userId: 'user-1',
        title: 'Event A',
        description: null,
        startAt: DateTime(2026, 8, 20, 8),
        endAt: DateTime(2026, 8, 20, 8, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final eventB = CalendarEvent(
        id: 'event-b',
        userId: 'user-1',
        title: 'Event B',
        description: null,
        startAt: DateTime(2026, 8, 20, 9),
        endAt: DateTime(2026, 8, 20, 9, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final eventC = CalendarEvent(
        id: 'event-c',
        userId: 'user-1',
        title: 'Event C',
        description: null,
        startAt: DateTime(2026, 8, 20, 10),
        endAt: DateTime(2026, 8, 20, 10, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final repository = _PendingDeleteCalendarRepository([
        eventA,
        eventB,
        eventC,
      ]);
      await _pumpCalendarPage(tester, repository: repository);

      // Delete eventB, the middle item (index 1): its tile enters the
      // loading state while the request is in flight.
      await tester.tap(find.byTooltip('Event actions').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.deleteCompleter.complete();
      await tester.pumpAndSettle();

      // eventB is gone. eventC, which shifted up into eventB's old list
      // index, must not have inherited eventB's loading state, and eventA
      // (untouched throughout) must remain unaffected.
      expect(find.text(eventB.title), findsNothing);
      expect(find.text(eventA.title), findsOneWidget);
      expect(find.text(eventC.title), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'prepending a newly created event does not transfer tile state to a '
    'different event',
    (tester) async {
      final eventA = CalendarEvent(
        id: 'event-a',
        userId: 'user-1',
        title: 'Event A',
        description: null,
        startAt: DateTime(2026, 8, 20, 9),
        endAt: DateTime(2026, 8, 20, 9, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final eventB = CalendarEvent(
        id: 'event-b',
        userId: 'user-1',
        title: 'Event B',
        description: null,
        startAt: DateTime(2026, 8, 20, 10),
        endAt: DateTime(2026, 8, 20, 10, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final newEvent = CalendarEvent(
        id: 'event-c',
        userId: 'user-1',
        title: 'Grab coffee',
        description: null,
        // Earlier than eventA/eventB, so it's prepended at index 0.
        startAt: DateTime(2026, 8, 20, 8),
        endAt: DateTime(2026, 8, 20, 8, 30),
        allDay: false,
        location: null,
        createdAt: DateTime(2026, 8, 13),
        updatedAt: DateTime(2026, 8, 13),
      );
      final repository = _PendingDeleteAndCreateCalendarRepository([
        eventA,
        eventB,
      ])..eventToCreate = newEvent;
      await _pumpCalendarPage(tester, repository: repository);

      // Start deleting eventA (index 0) and leave it mid-flight (loading).
      await tester.tap(find.byTooltip('Event actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Create a new event: it's prepended at index 0, shifting eventA to
      // index 1 and eventB to index 2.
      //
      // eventA's indeterminate spinner is still animating throughout this
      // flow, so `pumpAndSettle` (which waits for animations to finish)
      // would never return -- bounded `pump`s are used instead.
      await tester.tap(find.byTooltip('Add event'));
      await _pumpFrames(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Grab coffee',
      );
      await tester.tap(find.text('Create event'));
      await _pumpFrames(tester);

      // The new event must not have inherited eventA's loading state, and
      // eventA must still be shown as loading in its new position.
      expect(find.text('Grab coffee'), findsOneWidget);
      expect(find.text(eventA.title), findsOneWidget);
      expect(find.text(eventB.title), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.deleteCompleter.complete();
      await tester.pumpAndSettle();
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
