import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/create_task_input.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_page.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';
import 'package:mobile_desktop/features/tasks/update_task_input.dart';

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

/// A repository whose `updateTask` succeeds, returning [taskToReturn] and
/// recording the task ID it was called with.
class _UpdatingTasksRepository extends TasksRepository {
  _UpdatingTasksRepository(this._tasks, this.taskToReturn) : super(Dio());

  final List<Task> _tasks;
  final Task taskToReturn;
  String? lastTaskId;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> updateTask(String taskId, UpdateTaskInput input) async {
    lastTaskId = taskId;
    return taskToReturn;
  }
}

class _FailingUpdateTasksRepository extends TasksRepository {
  _FailingUpdateTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> updateTask(String taskId, UpdateTaskInput input) async {
    throw Exception('update failed');
  }
}

/// A repository whose `deleteTask` succeeds, recording every call.
class _DeletingTasksRepository extends TasksRepository {
  _DeletingTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;
  int deleteCallCount = 0;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<void> deleteTask(String taskId) async {
    deleteCallCount++;
  }
}

class _FailingDeleteTasksRepository extends TasksRepository {
  _FailingDeleteTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<void> deleteTask(String taskId) async {
    throw Exception('delete failed');
  }
}

/// A repository whose `deleteTask` doesn't resolve until [deleteCompleter]
/// is completed, so a test can observe the deleting tile's loading state
/// before letting the task actually disappear from the list.
class _PendingDeleteTasksRepository extends TasksRepository {
  _PendingDeleteTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;
  final deleteCompleter = Completer<void>();

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<void> deleteTask(String taskId) => deleteCompleter.future;
}

/// A repository whose `completeTask` doesn't resolve until
/// [completeCompleter] is completed, and whose `createTask` immediately
/// returns [taskToCreate] -- so a test can keep one task mid-mutation while
/// creating (and prepending) a different task.
class _PendingCompleteAndCreateTasksRepository extends TasksRepository {
  _PendingCompleteAndCreateTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;
  final completeCompleter = Completer<Task>();
  Task? taskToCreate;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> completeTask(String taskId) => completeCompleter.future;

  @override
  Future<Task> createTask(CreateTaskInput input) async => taskToCreate!;
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

Future<void> _openTaskMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Task actions'));
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

  testWidgets('edit sheet is prefilled with the current task values', (
    tester,
  ) async {
    final task = Task(
      id: 'task-1',
      userId: 'user-1',
      title: 'Buy milk',
      description: 'Whole milk, 1L',
      status: TaskStatus.open,
      priority: TaskPriority.high,
      projectId: null,
      goalId: null,
      dueDate: null,
      dueTime: null,
      createdAt: DateTime.utc(2026, 8, 10),
      updatedAt: DateTime.utc(2026, 8, 10),
      completedAt: null,
    );
    await _pumpTasksPage(tester, repository: _FakeTasksRepository([task]));

    await _openTaskMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);

    final titleField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Title'),
    );
    expect(titleField.controller!.text, 'Buy milk');

    final descriptionField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Description (optional)'),
    );
    expect(descriptionField.controller!.text, 'Whole milk, 1L');

    final segmentedButton = tester.widget<SegmentedButton<TaskPriority>>(
      find.byType(SegmentedButton<TaskPriority>),
    );
    expect(segmentedButton.selected, {TaskPriority.high});
  });

  testWidgets('editing a task submits the update and reflects it in the list', (
    tester,
  ) async {
    final task = _openTask;
    final updatedTask = Task(
      id: task.id,
      userId: task.userId,
      title: 'Buy oat milk',
      description: task.description,
      status: task.status,
      priority: task.priority,
      projectId: null,
      goalId: null,
      dueDate: null,
      dueTime: null,
      createdAt: task.createdAt,
      updatedAt: DateTime.utc(2026, 8, 13),
      completedAt: null,
    );
    final repository = _UpdatingTasksRepository([task], updatedTask);
    await _pumpTasksPage(tester, repository: repository);

    await _openTaskMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Buy oat milk',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repository.lastTaskId, task.id);
    expect(find.text('Edit task'), findsNothing);
    expect(find.text('Buy oat milk'), findsOneWidget);
  });

  testWidgets('a failed edit shows an inline error and keeps the sheet open', (
    tester,
  ) async {
    await _pumpTasksPage(
      tester,
      repository: _FailingUpdateTasksRepository([_openTask]),
    );

    await _openTaskMenu(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);
    expect(find.textContaining('update failed'), findsOneWidget);
  });

  testWidgets(
    'edit sheet lays out without overflow in a small windowed desktop size',
    (tester) async {
      tester.view.physicalSize = const Size(400, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpTasksPage(
        tester,
        repository: _FakeTasksRepository([_openTask]),
      );
      await _openTaskMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    },
  );

  testWidgets('canceling the delete confirmation keeps the task', (
    tester,
  ) async {
    final repository = _DeletingTasksRepository([_openTask]);
    await _pumpTasksPage(tester, repository: repository);

    await _openTaskMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete task?'), findsOneWidget);
    expect(find.textContaining(_openTask.title), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 0);
    expect(find.text(_openTask.title), findsOneWidget);
  });

  testWidgets('confirming delete removes the task from the list', (
    tester,
  ) async {
    final repository = _DeletingTasksRepository([_openTask]);
    await _pumpTasksPage(tester, repository: repository);

    await _openTaskMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 1);
    expect(find.text(_openTask.title), findsNothing);
    expect(find.text('No tasks yet.'), findsOneWidget);
  });

  testWidgets('a failed delete shows an error and keeps the task in the list', (
    tester,
  ) async {
    await _pumpTasksPage(
      tester,
      repository: _FailingDeleteTasksRepository([_openTask]),
    );

    await _openTaskMenu(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to delete task'), findsOneWidget);
    expect(find.text(_openTask.title), findsOneWidget);
  });

  testWidgets(
    'deleting a task while its tile is loading does not leave a different '
    'remaining task stuck loading',
    (tester) async {
      final taskA = Task(
        id: 'task-1',
        userId: 'user-1',
        title: 'Task A',
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
      final taskB = Task(
        id: 'task-2',
        userId: 'user-1',
        title: 'Task B',
        description: null,
        status: TaskStatus.open,
        priority: TaskPriority.normal,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        completedAt: null,
      );
      final repository = _PendingDeleteTasksRepository([taskA, taskB]);
      await _pumpTasksPage(tester, repository: repository);

      // Start deleting taskA (index 0): its tile enters the loading state
      // while the request is in flight.
      await tester.tap(find.byTooltip('Task actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.deleteCompleter.complete();
      await tester.pumpAndSettle();

      // taskA is gone. taskB, which shifted into taskA's old list index,
      // must not have inherited taskA's loading state.
      expect(find.text(taskA.title), findsNothing);
      expect(find.text(taskB.title), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Mark as complete'), findsOneWidget);

      // The popup menu must be enabled, not stuck disabled from taskA's
      // in-flight mutation.
      await tester.tap(find.byTooltip('Task actions'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'removing a middle task does not transfer tile state to the next task',
    (tester) async {
      final taskA = Task(
        id: 'task-1',
        userId: 'user-1',
        title: 'Task A',
        description: null,
        status: TaskStatus.open,
        priority: TaskPriority.normal,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: DateTime.utc(2026, 8, 11),
        updatedAt: DateTime.utc(2026, 8, 11),
        completedAt: null,
      );
      final taskB = Task(
        id: 'task-2',
        userId: 'user-1',
        title: 'Task B',
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
      final taskC = Task(
        id: 'task-3',
        userId: 'user-1',
        title: 'Task C',
        description: null,
        status: TaskStatus.open,
        priority: TaskPriority.normal,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        completedAt: null,
      );
      final repository = _PendingDeleteTasksRepository([taskA, taskB, taskC]);
      await _pumpTasksPage(tester, repository: repository);

      // Delete taskB, the middle item (index 1): its tile enters the
      // loading state while the request is in flight.
      await tester.tap(find.byTooltip('Task actions').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.deleteCompleter.complete();
      await tester.pumpAndSettle();

      // taskB is gone. taskC, which shifted up into taskB's old list index,
      // must not have inherited taskB's loading state, and taskA (untouched
      // throughout) must remain unaffected.
      expect(find.text(taskB.title), findsNothing);
      expect(find.text(taskA.title), findsOneWidget);
      expect(find.text(taskC.title), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Mark as complete'), findsNWidgets(2));
    },
  );

  testWidgets(
    'prepending a newly created task does not transfer tile state to a '
    'different task',
    (tester) async {
      final taskA = Task(
        id: 'task-1',
        userId: 'user-1',
        title: 'Task A',
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
      final taskB = Task(
        id: 'task-2',
        userId: 'user-1',
        title: 'Task B',
        description: null,
        status: TaskStatus.open,
        priority: TaskPriority.normal,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        completedAt: null,
      );
      final newTask = Task(
        id: 'task-3',
        userId: 'user-1',
        // Deliberately distinct from the create sheet's own "New task"
        // heading text, so the two can't be confused by a text finder.
        title: 'Grab coffee',
        description: null,
        status: TaskStatus.open,
        priority: TaskPriority.normal,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: DateTime.utc(2026, 8, 13),
        updatedAt: DateTime.utc(2026, 8, 13),
        completedAt: null,
      );
      final repository = _PendingCompleteAndCreateTasksRepository([
        taskA,
        taskB,
      ])..taskToCreate = newTask;
      await _pumpTasksPage(tester, repository: repository);

      // Put taskA (index 0) into a mid-mutation loading state and leave it
      // there.
      await tester.tap(find.byTooltip('Mark as complete').first);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Create a new task: it's prepended at index 0, shifting taskA to
      // index 1 and taskB to index 2.
      //
      // taskA's indeterminate spinner is still animating throughout this
      // flow, so `pumpAndSettle` (which waits for animations to finish)
      // would never return -- bounded `pump`s are used instead.
      await tester.tap(find.byTooltip('Add task'));
      await _pumpFrames(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Grab coffee',
      );
      await tester.tap(find.text('Create task'));
      await _pumpFrames(tester);

      // The new task must not have inherited taskA's loading state, and
      // taskA must still be shown as loading in its new position.
      expect(find.text('Grab coffee'), findsOneWidget);
      expect(find.text(taskA.title), findsOneWidget);
      expect(find.text(taskB.title), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Mark as complete'), findsNWidgets(2));

      repository.completeCompleter.complete(
        Task(
          id: taskA.id,
          userId: taskA.userId,
          title: taskA.title,
          description: taskA.description,
          status: TaskStatus.completed,
          priority: taskA.priority,
          projectId: null,
          goalId: null,
          dueDate: null,
          dueTime: null,
          createdAt: taskA.createdAt,
          updatedAt: DateTime.utc(2026, 8, 13),
          completedAt: DateTime.utc(2026, 8, 13),
        ),
      );
      await tester.pumpAndSettle();
    },
  );
}
