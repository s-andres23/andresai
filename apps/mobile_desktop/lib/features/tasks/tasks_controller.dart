import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'task.dart';
import 'tasks_repository.dart';

/// Loads and holds the authenticated user's tasks.
///
/// Exposes loading/data/error via [AsyncValue] so the UI reacts to each
/// state without manual bookkeeping.
class TasksController extends AsyncNotifier<List<Task>> {
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
