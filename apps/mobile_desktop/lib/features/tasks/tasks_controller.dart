import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'create_task_input.dart';
import 'task.dart';
import 'tasks_repository.dart';

/// Loads and holds the authenticated user's tasks.
///
/// Exposes loading/data/error via [AsyncValue] so the UI reacts to each
/// state without manual bookkeeping.
class TasksController extends AsyncNotifier<List<Task>> {
  bool _isCreating = false;
  final Set<String> _pendingTaskIds = {};

  @override
  Future<List<Task>> build() {
    return ref.watch(tasksRepositoryProvider).fetchTasks();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(tasksRepositoryProvider).fetchTasks(),
    );
  }

  /// Creates a task and prepends it to the current list.
  ///
  /// Guards against duplicate submission with [_isCreating]. On failure the
  /// error is rethrown to the caller (so the UI can show it) rather than
  /// written to [state], which would replace the loaded task list with an
  /// error view.
  Future<void> createTask(CreateTaskInput input) async {
    if (_isCreating) return;
    _isCreating = true;
    try {
      final created = await ref.read(tasksRepositoryProvider).createTask(input);
      state = AsyncValue.data([created, ...?state.value]);
    } finally {
      _isCreating = false;
    }
  }

  /// Marks [taskId] as completed and replaces it in place in the loaded
  /// list.
  Future<void> completeTask(String taskId) =>
      _updateTaskStatus(taskId, complete: true);

  /// Reopens [taskId] and replaces it in place in the loaded list.
  Future<void> reopenTask(String taskId) =>
      _updateTaskStatus(taskId, complete: false);

  /// Guards against concurrent complete/reopen calls for the same task with
  /// [_pendingTaskIds]. On failure the error is rethrown to the caller (so
  /// the UI can show it) rather than written to [state], which would
  /// replace the loaded task list with an error view.
  Future<void> _updateTaskStatus(
    String taskId, {
    required bool complete,
  }) async {
    if (_pendingTaskIds.contains(taskId)) return;
    _pendingTaskIds.add(taskId);
    try {
      final repository = ref.read(tasksRepositoryProvider);
      final updated = complete
          ? await repository.completeTask(taskId)
          : await repository.reopenTask(taskId);
      state = AsyncValue.data([
        for (final task in state.value ?? const [])
          if (task.id == taskId) updated else task,
      ]);
    } finally {
      _pendingTaskIds.remove(taskId);
    }
  }
}

final tasksControllerProvider =
    AsyncNotifierProvider<TasksController, List<Task>>(
      TasksController.new,
      // Dispose state as soon as nothing watches it (e.g. on sign-out, when
      // TasksPage unmounts), so tasks never leak between users/sessions.
      isAutoDispose: true,
      // Riverpod retries a failed build with exponential backoff by default;
      // disable that so a failed GET /tasks reaches the UI error state
      // immediately. The Retry button / refresh() remain the user-driven
      // retry mechanism.
      retry: (retryCount, error) => null,
    );
