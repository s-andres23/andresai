import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_page.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';

final _openTask = Task(
  id: 'task-1',
  userId: 'user-1',
  title: 'Buy milk',
  description: null,
  status: TaskStatus.open,
  priority: TaskPriority.normal,
  projectId: null,
  goalId: null,
  dueDate: null,
  dueTime: null,
  createdAt: DateTime.utc(2026, 8, 10),
  updatedAt: DateTime.utc(2026, 8, 10),
  completedAt: null,
);

final _completedTask = Task(
  id: 'task-2',
  userId: 'user-1',
  title: 'Write report',
  description: null,
  status: TaskStatus.completed,
  priority: TaskPriority.normal,
  projectId: null,
  goalId: null,
  dueDate: null,
  dueTime: null,
  createdAt: DateTime.utc(2026, 8, 9),
  updatedAt: DateTime.utc(2026, 8, 9),
  completedAt: DateTime.utc(2026, 8, 9),
);

class _FakeTasksRepository extends TasksRepository {
  _FakeTasksRepository([this._tasks = const []]) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;
}

/// A repository whose `completeTask`/`reopenTask` don't resolve until the
/// matching completer is completed, so a test can observe the loading
/// state before letting the request finish.
class _PendingStatusUpdateTasksRepository extends TasksRepository {
  _PendingStatusUpdateTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;
  final completeCompleter = Completer<Task>();
  final reopenCompleter = Completer<Task>();

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> completeTask(String taskId) => completeCompleter.future;

  @override
  Future<Task> reopenTask(String taskId) => reopenCompleter.future;
}

class _FailingStatusUpdateTasksRepository extends TasksRepository {
  _FailingStatusUpdateTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> completeTask(String taskId) async {
    throw Exception('complete failed');
  }

  @override
  Future<Task> reopenTask(String taskId) async {
    throw Exception('reopen failed');
  }
}

Future<void> _pumpTasksPage(
  WidgetTester tester, {
  TasksRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          repository ?? _FakeTasksRepository(),
        ),
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

  testWidgets(
    'tapping an open task shows a loading state, then marks it complete',
    (tester) async {
      final repository = _PendingStatusUpdateTasksRepository([_openTask]);
      await _pumpTasksPage(tester, repository: repository);

      expect(find.byTooltip('Mark as complete'), findsOneWidget);

      await tester.tap(find.byTooltip('Mark as complete'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Mark as complete'), findsNothing);

      repository.completeCompleter.complete(
        Task(
          id: _openTask.id,
          userId: _openTask.userId,
          title: _openTask.title,
          description: _openTask.description,
          status: TaskStatus.completed,
          priority: _openTask.priority,
          projectId: null,
          goalId: null,
          dueDate: null,
          dueTime: null,
          createdAt: _openTask.createdAt,
          updatedAt: DateTime.utc(2026, 8, 13),
          completedAt: DateTime.utc(2026, 8, 13),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reopen task'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('tapping a completed task reopens it', (tester) async {
    final repository = _PendingStatusUpdateTasksRepository([_completedTask]);
    await _pumpTasksPage(tester, repository: repository);

    expect(find.byTooltip('Reopen task'), findsOneWidget);

    await tester.tap(find.byTooltip('Reopen task'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.reopenCompleter.complete(
      Task(
        id: _completedTask.id,
        userId: _completedTask.userId,
        title: _completedTask.title,
        description: _completedTask.description,
        status: TaskStatus.open,
        priority: _completedTask.priority,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: _completedTask.createdAt,
        updatedAt: DateTime.utc(2026, 8, 13),
        completedAt: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Mark as complete'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'a failed complete action shows an error and keeps the task open',
    (tester) async {
      await _pumpTasksPage(
        tester,
        repository: _FailingStatusUpdateTasksRepository([_openTask]),
      );

      await tester.tap(find.byTooltip('Mark as complete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to update task'), findsOneWidget);
      expect(find.byTooltip('Mark as complete'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed reopen action shows an error and keeps the task completed',
    (tester) async {
      await _pumpTasksPage(
        tester,
        repository: _FailingStatusUpdateTasksRepository([_completedTask]),
      );

      await tester.tap(find.byTooltip('Reopen task'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to update task'), findsOneWidget);
      expect(find.byTooltip('Reopen task'), findsOneWidget);
    },
  );
}
