import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/create_task_input.dart';
import 'package:mobile_desktop/features/tasks/task.dart';
import 'package:mobile_desktop/features/tasks/tasks_repository.dart';
import 'package:mobile_desktop/features/tasks/update_task_input.dart';

/// Returns a fixed JSON body for every request, without performing any real
/// network I/O.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final String body;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Returns an empty `204 No Content` response for every request, matching
/// what the backend's `DELETE /tasks/:id` endpoint responds with.
class _NoContentAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('fetchTasks calls GET /tasks and parses the response', () async {
    final adapter = _StubAdapter(
      jsonEncode([
        {
          'id': 'task-1',
          'userId': 'user-1',
          'title': 'Buy milk',
          'description': null,
          'status': 'open',
          'priority': 'normal',
          'dueDate': null,
          'dueTime': null,
          'createdAt': '2026-08-10T12:00:00.000Z',
          'updatedAt': '2026-08-10T12:00:00.000Z',
          'completedAt': null,
        },
      ]),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = TasksRepository(dio);

    final tasks = await repository.fetchTasks();

    expect(adapter.lastOptions!.path, '/tasks');
    expect(adapter.lastOptions!.method, 'GET');
    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'Buy milk');
    expect(tasks.single.status, TaskStatus.open);
  });

  test('fetchTasks returns an empty list for an empty response', () async {
    final dio = Dio()..httpClientAdapter = _StubAdapter(jsonEncode([]));
    final repository = TasksRepository(dio);

    final tasks = await repository.fetchTasks();

    expect(tasks, isEmpty);
  });

  test(
    'createTask posts the full payload and parses the created task',
    () async {
      final adapter = _StubAdapter(
        jsonEncode({
          'id': 'task-2',
          'userId': 'user-1',
          'title': 'Write report',
          'description': 'Quarterly summary',
          'status': 'open',
          'priority': 'high',
          'dueDate': null,
          'dueTime': null,
          'createdAt': '2026-08-12T12:00:00.000Z',
          'updatedAt': '2026-08-12T12:00:00.000Z',
          'completedAt': null,
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = TasksRepository(dio);

      final task = await repository.createTask(
        const CreateTaskInput(
          title: 'Write report',
          description: 'Quarterly summary',
          priority: TaskPriority.high,
        ),
      );

      expect(adapter.lastOptions!.path, '/tasks');
      expect(adapter.lastOptions!.method, 'POST');
      expect(adapter.lastOptions!.data, {
        'title': 'Write report',
        'description': 'Quarterly summary',
        'priority': 'high',
      });
      expect(task.id, 'task-2');
      expect(task.priority, TaskPriority.high);
    },
  );

  test(
    'createTask omits description and priority from the payload when absent',
    () async {
      final adapter = _StubAdapter(
        jsonEncode({
          'id': 'task-3',
          'userId': 'user-1',
          'title': 'Buy milk',
          'description': null,
          'status': 'open',
          'priority': 'normal',
          'dueDate': null,
          'dueTime': null,
          'createdAt': '2026-08-12T12:00:00.000Z',
          'updatedAt': '2026-08-12T12:00:00.000Z',
          'completedAt': null,
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = TasksRepository(dio);

      await repository.createTask(const CreateTaskInput(title: 'Buy milk'));

      expect(adapter.lastOptions!.data, {'title': 'Buy milk'});
    },
  );

  test(
    'completeTask posts to /tasks/:id/complete and parses the updated task',
    () async {
      final adapter = _StubAdapter(
        jsonEncode({
          'id': 'task-1',
          'userId': 'user-1',
          'title': 'Buy milk',
          'description': null,
          'status': 'completed',
          'priority': 'normal',
          'dueDate': null,
          'dueTime': null,
          'createdAt': '2026-08-10T12:00:00.000Z',
          'updatedAt': '2026-08-13T12:00:00.000Z',
          'completedAt': '2026-08-13T12:00:00.000Z',
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = TasksRepository(dio);

      final task = await repository.completeTask('task-1');

      expect(adapter.lastOptions!.path, '/tasks/task-1/complete');
      expect(adapter.lastOptions!.method, 'POST');
      expect(task.status, TaskStatus.completed);
      expect(task.completedAt, isNotNull);
    },
  );

  test(
    'reopenTask posts to /tasks/:id/reopen and parses the updated task',
    () async {
      final adapter = _StubAdapter(
        jsonEncode({
          'id': 'task-1',
          'userId': 'user-1',
          'title': 'Buy milk',
          'description': null,
          'status': 'open',
          'priority': 'normal',
          'dueDate': null,
          'dueTime': null,
          'createdAt': '2026-08-10T12:00:00.000Z',
          'updatedAt': '2026-08-13T12:00:00.000Z',
          'completedAt': null,
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = TasksRepository(dio);

      final task = await repository.reopenTask('task-1');

      expect(adapter.lastOptions!.path, '/tasks/task-1/reopen');
      expect(adapter.lastOptions!.method, 'POST');
      expect(task.status, TaskStatus.open);
      expect(task.completedAt, isNull);
    },
  );

  test('updateTask patches /tasks/:id with the full payload and parses the '
      'response', () async {
    final adapter = _StubAdapter(
      jsonEncode({
        'id': 'task-1',
        'userId': 'user-1',
        'title': 'Buy oat milk',
        'description': 'From the corner store',
        'status': 'open',
        'priority': 'high',
        'dueDate': null,
        'dueTime': null,
        'createdAt': '2026-08-10T12:00:00.000Z',
        'updatedAt': '2026-08-13T12:00:00.000Z',
        'completedAt': null,
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = TasksRepository(dio);

    final task = await repository.updateTask(
      'task-1',
      const UpdateTaskInput(
        title: 'Buy oat milk',
        description: 'From the corner store',
        priority: TaskPriority.high,
      ),
    );

    expect(adapter.lastOptions!.path, '/tasks/task-1');
    expect(adapter.lastOptions!.method, 'PATCH');
    expect(adapter.lastOptions!.data, {
      'title': 'Buy oat milk',
      'description': 'From the corner store',
      'priority': 'high',
    });
    expect(task.title, 'Buy oat milk');
    expect(task.description, 'From the corner store');
    expect(task.priority, TaskPriority.high);
  });

  test(
    'updateTask sends an explicit null to clear an existing description',
    () async {
      final adapter = _StubAdapter(
        jsonEncode({
          'id': 'task-1',
          'userId': 'user-1',
          'title': 'Buy milk',
          'description': null,
          'status': 'open',
          'priority': 'normal',
          'dueDate': null,
          'dueTime': null,
          'createdAt': '2026-08-10T12:00:00.000Z',
          'updatedAt': '2026-08-13T12:00:00.000Z',
          'completedAt': null,
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = TasksRepository(dio);

      await repository.updateTask(
        'task-1',
        const UpdateTaskInput(title: 'Buy milk', priority: TaskPriority.normal),
      );

      expect(adapter.lastOptions!.data, {
        'title': 'Buy milk',
        'description': null,
        'priority': 'normal',
      });
    },
  );

  test('deleteTask sends DELETE /tasks/:id', () async {
    final adapter = _NoContentAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = TasksRepository(dio);

    await repository.deleteTask('task-1');

    expect(adapter.lastOptions!.path, '/tasks/task-1');
    expect(adapter.lastOptions!.method, 'DELETE');
  });
}
