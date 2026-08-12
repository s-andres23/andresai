import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
