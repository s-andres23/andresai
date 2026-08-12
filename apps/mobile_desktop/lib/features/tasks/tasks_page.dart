import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'create_task_input.dart';
import 'task.dart';
import 'tasks_controller.dart';

/// Displays the authenticated user's tasks, and lets the user create new
/// ones.
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const _CreateTaskSheet(),
        ),
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
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

/// A form for creating a task, shown as a modal bottom sheet.
class _CreateTaskSheet extends ConsumerStatefulWidget {
  const _CreateTaskSheet();

  @override
  ConsumerState<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends ConsumerState<_CreateTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  TaskPriority _priority = TaskPriority.normal;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final description = _descriptionController.text.trim();
    final input = CreateTaskInput(
      title: _titleController.text.trim(),
      description: description.isEmpty ? null : description,
      priority: _priority,
    );

    try {
      await ref.read(tasksControllerProvider.notifier).createTask(input);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // `useSafeArea` on showModalBottomSheet only avoids top/left/right system
    // intrusions, so the bottom safe area (e.g. the iOS home indicator) is
    // still ours to handle here, alongside the software keyboard inset.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          // Caps the form's width so it doesn't stretch edge-to-edge in
          // large desktop windows, without affecting narrower mobile/windowed
          // layouts, which stay full-width.
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: bottomInset + 16,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'New task',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                    textInputAction: TextInputAction.next,
                    autofocus: true,
                    enabled: !_isSubmitting,
                    validator: (value) =>
                        CreateTaskInput.validateTitle(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                    enabled: !_isSubmitting,
                    validator: (value) =>
                        CreateTaskInput.validateDescription(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<TaskPriority>(
                    segments: const [
                      ButtonSegment(
                        value: TaskPriority.low,
                        label: Text('Low'),
                      ),
                      ButtonSegment(
                        value: TaskPriority.normal,
                        label: Text('Normal'),
                      ),
                      ButtonSegment(
                        value: TaskPriority.high,
                        label: Text('High'),
                      ),
                    ],
                    selected: {_priority},
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (selection) =>
                              setState(() => _priority = selection.first),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _submitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create task'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
