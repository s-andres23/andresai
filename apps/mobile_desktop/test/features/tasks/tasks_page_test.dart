import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_page.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';

class _FakeTasksRepository extends TasksRepository {
  _FakeTasksRepository() : super(Dio());

  @override
  Future<List<Task>> fetchTasks() async => const [];
}

Future<void> _pumpTasksPage(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(_FakeTasksRepository()),
      ],
      child: const MaterialApp(home: TasksPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCreateTaskSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add task'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create-task sheet lays out without overflow in a small windowed '
      'desktop size', (tester) async {
    // Simulates a small macOS/Windows windowed app, which is where the
    // sheet used to get cut off before it was made scrollable.
    tester.view.physicalSize = const Size(400, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTasksPage(tester);
    await _openCreateTaskSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Create task'), findsOneWidget);
  });

  testWidgets(
    'create-task sheet remains usable when a software keyboard is open',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      // Simulates a software keyboard covering roughly half the screen.
      tester.view.viewInsets = const FakeViewPadding(bottom: 420);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await _pumpTasksPage(tester);
      await _openCreateTaskSheet(tester);

      expect(tester.takeException(), isNull);

      // The submit button must still be reachable by scrolling into view.
      await tester.ensureVisible(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create task'), findsOneWidget);
    },
  );

  testWidgets('create-task sheet caps its width on a large desktop window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpTasksPage(tester);
    await _openCreateTaskSheet(tester);

    final formWidth = tester.getSize(find.byType(Form)).width;

    expect(formWidth, lessThanOrEqualTo(480));
  });

  testWidgets(
    'create-task sheet uses the full available width on a narrow mobile '
    'screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpTasksPage(tester);
      await _openCreateTaskSheet(tester);

      final formWidth = tester.getSize(find.byType(Form)).width;

      // 390 logical px screen minus the sheet's 16px horizontal padding.
      expect(formWidth, closeTo(390 - 32, 1));
    },
  );
}
