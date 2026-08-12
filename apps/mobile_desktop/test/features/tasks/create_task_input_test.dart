import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/tasks/create_task_input.dart';
import 'package:mobile_desktop/features/tasks/task.dart';

void main() {
  group('CreateTaskInput.validateTitle', () {
    test('rejects an empty title', () {
      expect(CreateTaskInput.validateTitle(''), isNotNull);
    });

    test('rejects a whitespace-only title', () {
      expect(CreateTaskInput.validateTitle('   '), isNotNull);
    });

    test('rejects a title over 200 characters', () {
      expect(CreateTaskInput.validateTitle('a' * 201), isNotNull);
    });

    test('accepts a title at exactly 200 characters', () {
      expect(CreateTaskInput.validateTitle('a' * 200), isNull);
    });

    test('accepts a valid title', () {
      expect(CreateTaskInput.validateTitle('Buy milk'), isNull);
    });
  });

  group('CreateTaskInput.validateDescription', () {
    test('accepts an empty description', () {
      expect(CreateTaskInput.validateDescription(''), isNull);
    });

    test('rejects a description over 2000 characters', () {
      expect(CreateTaskInput.validateDescription('a' * 2001), isNotNull);
    });

    test('accepts a description at exactly 2000 characters', () {
      expect(CreateTaskInput.validateDescription('a' * 2000), isNull);
    });
  });

  group('CreateTaskInput.toJson', () {
    test(
      'includes only the title when description and priority are absent',
      () {
        const input = CreateTaskInput(title: 'Buy milk');

        expect(input.toJson(), {'title': 'Buy milk'});
      },
    );

    test('includes description and priority when present', () {
      const input = CreateTaskInput(
        title: 'Write report',
        description: 'Quarterly summary',
        priority: TaskPriority.high,
      );

      expect(input.toJson(), {
        'title': 'Write report',
        'description': 'Quarterly summary',
        'priority': 'high',
      });
    });
  });
}
