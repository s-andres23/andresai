import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'task.dart';
import 'tasks_controller.dart';

/// Displays the authenticated user's tasks. Read-only for now.
class TasksPage extends ConsumerWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksState = ref.watch(tasksControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: switch (tasksState) {
        AsyncData(:final value) => _TasksList(tasks: value),
        AsyncError(:final error) => _TasksErrorView(
          message: error.toString(),
          onRetry: () => ref.read(tasksControllerProvider.notifier).refresh(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TasksList extends StatelessWidget {
  const _TasksList({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Center(child: Text('No tasks yet.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _TaskTile(task: tasks[index]),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == TaskStatus.completed;

    return Card(
      child: ListTile(
        leading: Icon(
          isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCompleted ? Colors.green : null,
        ),
        title: Text(
          task.title,
          style: isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: task.description == null ? null : Text(task.description!),
        trailing: Text(task.priority.name),
      ),
    );
  }
}

class _TasksErrorView extends StatelessWidget {
  const _TasksErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load tasks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
