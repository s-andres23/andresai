import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'task.dart';

/// Fetches the authenticated user's tasks from the NestJS backend.
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
}

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(ref.watch(apiClientProvider));
});
