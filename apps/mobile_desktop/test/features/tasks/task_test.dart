import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/task.dart';

void main() {
  group('Task.fromJson', () {
    test('parses a fully populated API response', () {
      final task = Task.fromJson({
        'id': 'task-1',
        'userId': 'user-1',
        'title': 'Buy milk',
        'description': 'Whole milk, 1L',
        'status': 'completed',
        'priority': 'high',
        'projectId': 'project-1',
        'goalId': 'goal-1',
        'dueDate': '2026-08-15',
        'dueTime': '09:30',
        'createdAt': '2026-08-10T12:00:00.000Z',
        'updatedAt': '2026-08-11T12:00:00.000Z',
        'completedAt': '2026-08-11T12:00:00.000Z',
      });

      expect(task.id, 'task-1');
      expect(task.userId, 'user-1');
      expect(task.title, 'Buy milk');
      expect(task.description, 'Whole milk, 1L');
      expect(task.status, TaskStatus.completed);
      expect(task.priority, TaskPriority.high);
      expect(task.projectId, 'project-1');
      expect(task.goalId, 'goal-1');
      expect(task.dueDate, '2026-08-15');
      expect(task.dueTime, '09:30');
      expect(task.createdAt, DateTime.parse('2026-08-10T12:00:00.000Z'));
      expect(task.updatedAt, DateTime.parse('2026-08-11T12:00:00.000Z'));
      expect(task.completedAt, DateTime.parse('2026-08-11T12:00:00.000Z'));
    });

    test('parses an open task with nullable fields absent', () {
      final task = Task.fromJson({
        'id': 'task-2',
        'userId': 'user-1',
        'title': 'Write report',
        'description': null,
        'status': 'open',
        'priority': 'normal',
        'dueDate': null,
        'dueTime': null,
        'createdAt': '2026-08-10T12:00:00.000Z',
        'updatedAt': '2026-08-10T12:00:00.000Z',
        'completedAt': null,
      });

      expect(task.status, TaskStatus.open);
      expect(task.priority, TaskPriority.normal);
      expect(task.description, isNull);
      expect(task.projectId, isNull);
      expect(task.goalId, isNull);
      expect(task.dueDate, isNull);
      expect(task.dueTime, isNull);
      expect(task.completedAt, isNull);
    });
  });
}
