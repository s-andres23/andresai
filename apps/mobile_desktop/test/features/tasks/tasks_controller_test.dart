import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/create_task_input.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_controller.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';

final _task = Task(
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

final _createdTask = Task(
  id: 'task-2',
  userId: 'user-1',
  title: 'Write report',
  description: null,
  status: TaskStatus.open,
  priority: TaskPriority.high,
  projectId: null,
  goalId: null,
  dueDate: null,
  dueTime: null,
  createdAt: DateTime.utc(2026, 8, 12),
  updatedAt: DateTime.utc(2026, 8, 12),
  completedAt: null,
);

final _completedTask = Task(
  id: 'task-1',
  userId: 'user-1',
  title: 'Buy milk',
  description: null,
  status: TaskStatus.completed,
  priority: TaskPriority.normal,
  projectId: null,
  goalId: null,
  dueDate: null,
  dueTime: null,
  createdAt: DateTime.utc(2026, 8, 10),
  updatedAt: DateTime.utc(2026, 8, 13),
  completedAt: DateTime.utc(2026, 8, 13),
);

final _reopenedTask = Task(
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
  updatedAt: DateTime.utc(2026, 8, 13),
  completedAt: null,
);

class _FakeTasksRepository extends TasksRepository {
  _FakeTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;
}

class _ThrowingTasksRepository extends TasksRepository {
  _ThrowingTasksRepository() : super(Dio());

  @override
  Future<List<Task>> fetchTasks() async {
    throw Exception('network error');
  }
}

/// A repository that fetches successfully but whose `createTask` succeeds,
/// returning [taskToCreate] and recording every call it receives.
class _CreatingTasksRepository extends TasksRepository {
  _CreatingTasksRepository(this._tasks, this.taskToCreate) : super(Dio());

  final List<Task> _tasks;
  final Task taskToCreate;
  int createTaskCallCount = 0;
  CreateTaskInput? lastInput;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> createTask(CreateTaskInput input) async {
    createTaskCallCount++;
    lastInput = input;
    return taskToCreate;
  }
}

/// A repository that fetches successfully but whose `createTask` always
/// fails.
class _FailingCreateTasksRepository extends TasksRepository {
  _FailingCreateTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> createTask(CreateTaskInput input) async {
    throw Exception('create failed');
  }
}

/// A repository whose `createTask` doesn't resolve until [complete] is
/// called, so tests can assert on behavior while a create is in flight.
class _DelayedCreateTasksRepository extends TasksRepository {
  _DelayedCreateTasksRepository(this._tasks, this.taskToCreate) : super(Dio());

  final List<Task> _tasks;
  final Task taskToCreate;
  final _completer = Completer<void>();
  int createTaskCallCount = 0;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> createTask(CreateTaskInput input) async {
    createTaskCallCount++;
    await _completer.future;
    return taskToCreate;
  }

  void complete() => _completer.complete();
}

/// A repository that fetches successfully, and whose `completeTask`/
/// `reopenTask` succeed, returning [taskToReturn] and recording every call.
class _StatusUpdatingTasksRepository extends TasksRepository {
  _StatusUpdatingTasksRepository(this._tasks, this.taskToReturn) : super(Dio());

  final List<Task> _tasks;
  final Task taskToReturn;
  int completeCallCount = 0;
  int reopenCallCount = 0;
  String? lastTaskId;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> completeTask(String taskId) async {
    completeCallCount++;
    lastTaskId = taskId;
    return taskToReturn;
  }

  @override
  Future<Task> reopenTask(String taskId) async {
    reopenCallCount++;
    lastTaskId = taskId;
    return taskToReturn;
  }
}

/// A repository that fetches successfully but whose `completeTask`/
/// `reopenTask` always fail.
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

/// A repository whose `completeTask`/`reopenTask` don't resolve until
/// [complete] is called for the matching task ID, so tests can assert on
/// behavior while an update is in flight.
class _DelayedStatusUpdateTasksRepository extends TasksRepository {
  _DelayedStatusUpdateTasksRepository(this._tasks, this._resultsByTaskId)
    : super(Dio());

  final List<Task> _tasks;
  final Map<String, Task> _resultsByTaskId;
  final Map<String, Completer<void>> _completers = {};
  final Map<String, int> completeCallCounts = {};

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> completeTask(String taskId) async {
    completeCallCounts.update(taskId, (count) => count + 1, ifAbsent: () => 1);
    await (_completers[taskId] ??= Completer<void>()).future;
    return _resultsByTaskId[taskId]!;
  }

  void complete(String taskId) {
    (_completers[taskId] ??= Completer<void>()).complete();
  }
}

void main() {
  test('starts in loading state and resolves to the loaded tasks', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          _FakeTasksRepository([_task]),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(tasksControllerProvider),
      isA<AsyncLoading<Object?>>(),
    );

    final tasks = await container.read(tasksControllerProvider.future);

    expect(tasks, [_task]);
    expect(container.read(tasksControllerProvider).value, [_task]);
  });

  test('exposes an error state when the repository throws', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(_ThrowingTasksRepository()),
      ],
    );
    addTearDown(container.dispose);

    // If automatic retry were still enabled, this would hang for several
    // seconds (Riverpod's default backoff) instead of failing immediately.
    await expectLater(
      container.read(tasksControllerProvider.future),
      throwsException,
    );
    expect(container.read(tasksControllerProvider), isA<AsyncError<Object?>>());
  });

  test('refresh() re-fetches tasks from the repository', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          _FakeTasksRepository([_task]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);
    await container.read(tasksControllerProvider.notifier).refresh();

    expect(container.read(tasksControllerProvider).value, [_task]);
  });

  test('disposes its state once nothing is watching it', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          _FakeTasksRepository([_task]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(tasksControllerProvider, (_, _) {});
    await container.read(tasksControllerProvider.future);
    expect(container.exists(tasksControllerProvider), isTrue);

    // Simulates TasksPage unmounting, e.g. on sign-out.
    subscription.close();
    await Future<void>.delayed(Duration.zero);

    expect(container.exists(tasksControllerProvider), isFalse);
  });

  test('createTask prepends the created task to the loaded list', () async {
    final repository = _CreatingTasksRepository([_task], _createdTask);
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);
    const input = CreateTaskInput(title: 'Write report');
    await container.read(tasksControllerProvider.notifier).createTask(input);

    expect(repository.createTaskCallCount, 1);
    expect(repository.lastInput, input);
    expect(container.read(tasksControllerProvider).value, [
      _createdTask,
      _task,
    ]);
  });

  test(
    'createTask surfaces errors to the caller without wiping the loaded list',
    () async {
      final container = ProviderContainer(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(
            _FailingCreateTasksRepository([_task]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(tasksControllerProvider.future);

      await expectLater(
        container
            .read(tasksControllerProvider.notifier)
            .createTask(const CreateTaskInput(title: 'Write report')),
        throwsException,
      );

      expect(
        container.read(tasksControllerProvider),
        isA<AsyncData<Object?>>(),
      );
      expect(container.read(tasksControllerProvider).value, [_task]);
    },
  );

  test(
    'createTask ignores a second call while one is already in flight',
    () async {
      final repository = _DelayedCreateTasksRepository([_task], _createdTask);
      final container = ProviderContainer(
        overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(tasksControllerProvider.future);

      final notifier = container.read(tasksControllerProvider.notifier);
      const input = CreateTaskInput(title: 'Write report');
      final first = notifier.createTask(input);
      final second = notifier.createTask(input);

      repository.complete();
      await first;
      await second;

      expect(repository.createTaskCallCount, 1);
      expect(container.read(tasksControllerProvider).value, [
        _createdTask,
        _task,
      ]);
    },
  );

  test('completeTask replaces the matching task in place', () async {
    final repository = _StatusUpdatingTasksRepository([
      _createdTask,
      _task,
    ], _completedTask);
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);
    await container
        .read(tasksControllerProvider.notifier)
        .completeTask(_task.id);

    expect(repository.completeCallCount, 1);
    expect(repository.lastTaskId, _task.id);
    expect(container.read(tasksControllerProvider).value, [
      _createdTask,
      _completedTask,
    ]);
  });

  test('reopenTask replaces the matching task in place', () async {
    final repository = _StatusUpdatingTasksRepository([
      _completedTask,
    ], _reopenedTask);
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);
    await container
        .read(tasksControllerProvider.notifier)
        .reopenTask(_completedTask.id);

    expect(repository.reopenCallCount, 1);
    expect(repository.lastTaskId, _completedTask.id);
    expect(container.read(tasksControllerProvider).value, [_reopenedTask]);
  });

  test('completeTask surfaces errors to the caller without wiping the loaded '
      'list', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          _FailingStatusUpdateTasksRepository([_task]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);

    await expectLater(
      container.read(tasksControllerProvider.notifier).completeTask(_task.id),
      throwsException,
    );

    expect(container.read(tasksControllerProvider), isA<AsyncData<Object?>>());
    expect(container.read(tasksControllerProvider).value, [_task]);
  });

  test(
    'reopenTask surfaces errors to the caller without wiping the loaded list',
    () async {
      final container = ProviderContainer(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(
            _FailingStatusUpdateTasksRepository([_completedTask]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(tasksControllerProvider.future);

      await expectLater(
        container
            .read(tasksControllerProvider.notifier)
            .reopenTask(_completedTask.id),
        throwsException,
      );

      expect(container.read(tasksControllerProvider).value, [_completedTask]);
    },
  );

  test('completeTask ignores a second call for the same task while one is '
      'already in flight', () async {
    final repository = _DelayedStatusUpdateTasksRepository(
      [_task],
      {_task.id: _completedTask},
    );
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);

    final notifier = container.read(tasksControllerProvider.notifier);
    final first = notifier.completeTask(_task.id);
    final second = notifier.completeTask(_task.id);

    repository.complete(_task.id);
    await first;
    await second;

    expect(repository.completeCallCounts[_task.id], 1);
    expect(container.read(tasksControllerProvider).value, [_completedTask]);
  });

  test('completeTask allows concurrent updates for different tasks', () async {
    final otherTask = Task(
      id: 'task-5',
      userId: 'user-1',
      title: 'Water plants',
      description: null,
      status: TaskStatus.open,
      priority: TaskPriority.low,
      projectId: null,
      goalId: null,
      dueDate: null,
      dueTime: null,
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      completedAt: null,
    );
    final otherCompletedTask = Task(
      id: otherTask.id,
      userId: otherTask.userId,
      title: otherTask.title,
      description: otherTask.description,
      status: TaskStatus.completed,
      priority: otherTask.priority,
      projectId: null,
      goalId: null,
      dueDate: null,
      dueTime: null,
      createdAt: otherTask.createdAt,
      updatedAt: DateTime.utc(2026, 8, 13),
      completedAt: DateTime.utc(2026, 8, 13),
    );
    final repository = _DelayedStatusUpdateTasksRepository(
      [_task, otherTask],
      {_task.id: _completedTask, otherTask.id: otherCompletedTask},
    );
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);

    final notifier = container.read(tasksControllerProvider.notifier);
    final first = notifier.completeTask(_task.id);
    final second = notifier.completeTask(otherTask.id);

    repository.complete(_task.id);
    repository.complete(otherTask.id);
    await first;
    await second;

    expect(repository.completeCallCounts[_task.id], 1);
    expect(repository.completeCallCounts[otherTask.id], 1);
    expect(container.read(tasksControllerProvider).value, [
      _completedTask,
      otherCompletedTask,
    ]);
  });
}
