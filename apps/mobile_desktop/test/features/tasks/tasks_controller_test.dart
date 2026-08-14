import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/create_task_input.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_controller.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';
import 'package:mobile_desktop/features/tasks/update_task_input.dart';

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

/// A repository that fetches successfully, and whose `updateTask` succeeds,
/// returning [taskToReturn] and recording every call.
class _UpdatingTasksRepository extends TasksRepository {
  _UpdatingTasksRepository(this._tasks, this.taskToReturn) : super(Dio());

  final List<Task> _tasks;
  final Task taskToReturn;
  int updateCallCount = 0;
  String? lastTaskId;
  UpdateTaskInput? lastInput;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> updateTask(String taskId, UpdateTaskInput input) async {
    updateCallCount++;
    lastTaskId = taskId;
    lastInput = input;
    return taskToReturn;
  }
}

/// A repository that fetches successfully but whose `updateTask` always
/// fails.
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

/// A repository that fetches successfully, and whose `deleteTask` succeeds,
/// recording every call.
class _DeletingTasksRepository extends TasksRepository {
  _DeletingTasksRepository(this._tasks) : super(Dio());

  final List<Task> _tasks;
  int deleteCallCount = 0;
  String? lastTaskId;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<void> deleteTask(String taskId) async {
    deleteCallCount++;
    lastTaskId = taskId;
  }
}

/// A repository that fetches successfully but whose `deleteTask` always
/// fails.
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

/// A repository whose `completeTask` and `updateTask` don't resolve until
/// [completeStatusUpdate]/[completeEdit] is called, so a test can verify
/// that different mutation types for the same task are mutually exclusive.
class _DelayedMixedMutationTasksRepository extends TasksRepository {
  _DelayedMixedMutationTasksRepository(
    this._tasks,
    this._completedResult,
    this._updatedResult,
  ) : super(Dio());

  final List<Task> _tasks;
  final Task _completedResult;
  final Task _updatedResult;
  final _statusCompleter = Completer<void>();
  final _editCompleter = Completer<void>();
  int completeCallCount = 0;
  int updateCallCount = 0;

  @override
  Future<List<Task>> fetchTasks() async => _tasks;

  @override
  Future<Task> completeTask(String taskId) async {
    completeCallCount++;
    await _statusCompleter.future;
    return _completedResult;
  }

  @override
  Future<Task> updateTask(String taskId, UpdateTaskInput input) async {
    updateCallCount++;
    await _editCompleter.future;
    return _updatedResult;
  }

  void completeStatusUpdate() => _statusCompleter.complete();
  void completeEdit() => _editCompleter.complete();
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

  test('updateTask replaces the matching task in place', () async {
    final updatedTask = Task(
      id: _task.id,
      userId: _task.userId,
      title: 'Buy oat milk',
      description: 'From the corner store',
      status: _task.status,
      priority: TaskPriority.high,
      projectId: null,
      goalId: null,
      dueDate: null,
      dueTime: null,
      createdAt: _task.createdAt,
      updatedAt: DateTime.utc(2026, 8, 13),
      completedAt: null,
    );
    final repository = _UpdatingTasksRepository([
      _createdTask,
      _task,
    ], updatedTask);
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);
    const input = UpdateTaskInput(
      title: 'Buy oat milk',
      description: 'From the corner store',
      priority: TaskPriority.high,
    );
    await container
        .read(tasksControllerProvider.notifier)
        .updateTask(_task.id, input);

    expect(repository.updateCallCount, 1);
    expect(repository.lastTaskId, _task.id);
    expect(repository.lastInput, input);
    expect(container.read(tasksControllerProvider).value, [
      _createdTask,
      updatedTask,
    ]);
  });

  test('updateTask surfaces errors to the caller without wiping the loaded '
      'list', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          _FailingUpdateTasksRepository([_task]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);

    await expectLater(
      container
          .read(tasksControllerProvider.notifier)
          .updateTask(
            _task.id,
            const UpdateTaskInput(
              title: 'Buy oat milk',
              priority: TaskPriority.normal,
            ),
          ),
      throwsException,
    );

    expect(container.read(tasksControllerProvider), isA<AsyncData<Object?>>());
    expect(container.read(tasksControllerProvider).value, [_task]);
  });

  test('deleteTask removes the task from the loaded list', () async {
    final repository = _DeletingTasksRepository([_createdTask, _task]);
    final container = ProviderContainer(
      overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);
    await container.read(tasksControllerProvider.notifier).deleteTask(_task.id);

    expect(repository.deleteCallCount, 1);
    expect(repository.lastTaskId, _task.id);
    expect(container.read(tasksControllerProvider).value, [_createdTask]);
  });

  test('deleteTask surfaces errors to the caller without wiping the loaded '
      'list', () async {
    final container = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(
          _FailingDeleteTasksRepository([_task]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.future);

    await expectLater(
      container.read(tasksControllerProvider.notifier).deleteTask(_task.id),
      throwsException,
    );

    expect(container.read(tasksControllerProvider).value, [_task]);
  });

  test(
    'a pending complete blocks a concurrent edit for the same task',
    () async {
      final updatedTask = Task(
        id: _task.id,
        userId: _task.userId,
        title: 'Buy oat milk',
        description: _task.description,
        status: _task.status,
        priority: _task.priority,
        projectId: null,
        goalId: null,
        dueDate: null,
        dueTime: null,
        createdAt: _task.createdAt,
        updatedAt: DateTime.utc(2026, 8, 13),
        completedAt: null,
      );
      final repository = _DelayedMixedMutationTasksRepository(
        [_task],
        _completedTask,
        updatedTask,
      );
      final container = ProviderContainer(
        overrides: [tasksRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(tasksControllerProvider.future);

      final notifier = container.read(tasksControllerProvider.notifier);
      // Started first, so it wins the guard: the concurrent edit below
      // should be silently ignored rather than racing it.
      final completeFuture = notifier.completeTask(_task.id);
      final editFuture = notifier.updateTask(
        _task.id,
        const UpdateTaskInput(
          title: 'Buy oat milk',
          priority: TaskPriority.normal,
        ),
      );

      repository.completeStatusUpdate();
      repository.completeEdit();
      await completeFuture;
      await editFuture;

      expect(repository.completeCallCount, 1);
      expect(repository.updateCallCount, 0);
      expect(container.read(tasksControllerProvider).value, [_completedTask]);
    },
  );
}
