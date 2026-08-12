import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'create_task_input.dart';
import 'task.dart';

/// Fetches and creates the authenticated user's tasks via the NestJS backend.
///
/// Uses the shared [apiClientProvider] Dio client; never talks to Supabase's
/// `tasks` table directly.
class TasksRepository {
  TasksRepository(this._dio);

  final Dio _dio;

  Future<List<Task>> fetchTasks() async {
    final response = await _dio.get<List<dynamic>>('/tasks');
    final data = response.data ?? const [];
    return data
        .map((task) => Task.fromJson(task as Map<String, dynamic>))
        .toList();
  }

  Future<Task> createTask(CreateTaskInput input) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tasks',
      data: input.toJson(),
    );
    return Task.fromJson(response.data!);
  }
}

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(ref.watch(apiClientProvider));
});
