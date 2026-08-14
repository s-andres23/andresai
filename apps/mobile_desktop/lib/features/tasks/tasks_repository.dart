import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'create_task_input.dart';
import 'task.dart';
import 'update_task_input.dart';

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

  Future<Task> completeTask(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tasks/$taskId/complete',
    );
    return Task.fromJson(response.data!);
  }

  Future<Task> reopenTask(String taskId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tasks/$taskId/reopen',
    );
    return Task.fromJson(response.data!);
  }

  Future<Task> updateTask(String taskId, UpdateTaskInput input) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/tasks/$taskId',
      data: input.toJson(),
    );
    return Task.fromJson(response.data!);
  }

  /// The backend responds `204 No Content` on success, so there's no body
  /// to parse.
  Future<void> deleteTask(String taskId) async {
    await _dio.delete<void>('/tasks/$taskId');
  }
}

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(ref.watch(apiClientProvider));
});
