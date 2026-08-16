import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/app/home_shell.dart';
import 'package:mobile_desktop/features/calendar/calendar_event.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';
import 'package:mobile_desktop/features/reminders/reminders_repository.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';

class _FakeTasksRepository extends TasksRepository {
  _FakeTasksRepository() : super(Dio());

  int fetchCallCount = 0;

  @override
  Future<List<Task>> fetchTasks() async {
    fetchCallCount++;
    return const [];
  }
}

class _FakeCalendarRepository extends CalendarRepository {
  _FakeCalendarRepository() : super(Dio());

  @override
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async => const [];
}

class _FakeRemindersRepository extends RemindersRepository {
  _FakeRemindersRepository() : super(Dio());

  int fetchCallCount = 0;

  @override
  Future<List<Reminder>> fetchReminders() async {
    fetchCallCount++;
    return const [];
  }
}

Future<void> _pumpHomeShell(
  WidgetTester tester, {
  TasksRepository? tasksRepository,
  RemindersRepository? remindersRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          tasksRepository ?? _FakeTasksRepository(),
        ),
        calendarRepositoryProvider.overrideWithValue(_FakeCalendarRepository()),
        remindersRepositoryProvider.overrideWithValue(
          remindersRepository ?? _FakeRemindersRepository(),
        ),
      ],
      child: const MaterialApp(home: HomeShell()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _navDestination(String label) =>
    find.widgetWithText(NavigationDestination, label);

int _selectedNavIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('starts on the Tasks tab', (tester) async {
    await _pumpHomeShell(tester);

    expect(_selectedNavIndex(tester), 0);
    expect(find.text('No tasks yet.'), findsOneWidget);
    expect(_navDestination('Tasks'), findsOneWidget);
    expect(_navDestination('Calendar'), findsOneWidget);
    expect(_navDestination('Reminders'), findsOneWidget);
  });

  testWidgets('switches to the Calendar tab and back', (tester) async {
    await _pumpHomeShell(tester);

    await tester.tap(_navDestination('Calendar'));
    await tester.pumpAndSettle();

    expect(_selectedNavIndex(tester), 1);
    expect(find.text('No events yet.'), findsOneWidget);
    // The Tasks tab's content is kept alive but offstage; the default
    // finders (which skip offstage widgets) correctly report it as not
    // currently shown.
    expect(find.text('No tasks yet.'), findsNothing);

    await tester.tap(_navDestination('Tasks'));
    await tester.pumpAndSettle();

    expect(_selectedNavIndex(tester), 0);
    expect(find.text('No tasks yet.'), findsOneWidget);
  });

  testWidgets('switches to the Reminders tab', (tester) async {
    await _pumpHomeShell(tester);

    await tester.tap(_navDestination('Reminders'));
    await tester.pumpAndSettle();

    expect(_selectedNavIndex(tester), 2);
    expect(find.text('No reminders yet.'), findsOneWidget);
    expect(find.text('No tasks yet.'), findsNothing);
  });

  testWidgets(
    'the Tasks tab\'s content still exists offstage while Calendar is '
    'selected (IndexedStack keeps it alive)',
    (tester) async {
      await _pumpHomeShell(tester);

      await tester.tap(_navDestination('Calendar'));
      await tester.pumpAndSettle();

      expect(find.text('No tasks yet.', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets('does not re-fetch a tab\'s data when switching back to it', (
    tester,
  ) async {
    final tasksRepository = _FakeTasksRepository();
    final remindersRepository = _FakeRemindersRepository();
    await _pumpHomeShell(
      tester,
      tasksRepository: tasksRepository,
      remindersRepository: remindersRepository,
    );

    expect(tasksRepository.fetchCallCount, 1);
    expect(remindersRepository.fetchCallCount, 1);

    await tester.tap(_navDestination('Reminders'));
    await tester.pumpAndSettle();
    await tester.tap(_navDestination('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(_navDestination('Tasks'));
    await tester.pumpAndSettle();

    // IndexedStack keeps every page (and its controller) alive while another
    // tab is selected, so returning to a tab must not trigger another fetch.
    expect(tasksRepository.fetchCallCount, 1);
    expect(remindersRepository.fetchCallCount, 1);
  });

  testWidgets('sign-out is available on each tab', (tester) async {
    await _pumpHomeShell(tester);

    expect(find.byTooltip('Sign out'), findsOneWidget);

    await tester.tap(_navDestination('Calendar'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sign out'), findsOneWidget);

    await tester.tap(_navDestination('Reminders'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sign out'), findsOneWidget);
  });
}
