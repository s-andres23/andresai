import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'create_task_input.dart';
import 'task.dart';
import 'tasks_controller.dart';
import 'update_task_input.dart';

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
      itemBuilder: (context, index) {
        final task = tasks[index];
        // A stable per-task key so Flutter matches each row's Element (and
        // its local _isUpdating state) to the same task across insertions,
        // deletions, and reorders, instead of reusing whatever State object
        // previously occupied that list index.
        return _TaskTile(key: ValueKey(task.id), task: task);
      },
      // Without this, ListView.separated only compares the old vs. new
      // widget at the *same* index: a keyed row whose task shifted to a
      // different index is discarded and rebuilt from scratch (losing its
      // _isUpdating state) rather than relocated. This lets Flutter find a
      // keyed row wherever it now lives and move its Element instead.
      findItemIndexCallback: (key) {
        final taskId = (key as ValueKey<String>).value;
        final index = tasks.indexWhere((task) => task.id == taskId);
        return index == -1 ? null : index;
      },
    );
  }
}

class _TaskTile extends ConsumerStatefulWidget {
  const _TaskTile({super.key, required this.task});

  final Task task;

  @override
  ConsumerState<_TaskTile> createState() => _TaskTileState();
}

enum _TaskAction { edit, delete }

class _TaskTileState extends ConsumerState<_TaskTile> {
  bool _isUpdating = false;

  Future<void> _toggleStatus() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    final isCompleted = widget.task.status == TaskStatus.completed;
    final notifier = ref.read(tasksControllerProvider.notifier);

    try {
      if (isCompleted) {
        await notifier.reopenTask(widget.task.id);
      } else {
        await notifier.completeTask(widget.task.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _openEditSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditTaskSheet(task: widget.task),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete "${widget.task.title}"? This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      await ref
          .read(tasksControllerProvider.notifier)
          .deleteTask(widget.task.id);
      // On success the task disappears from the list entirely once `state`
      // updates, so there's no tile left to reset `_isUpdating` on.
    } catch (error) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete task: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = task.status == TaskStatus.completed;

    return Card(
      child: ListTile(
        leading: _isUpdating
            ? const Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: Icon(
                  isCompleted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isCompleted ? Colors.green : null,
                ),
                tooltip: isCompleted ? 'Reopen task' : 'Mark as complete',
                onPressed: _toggleStatus,
              ),
        title: Text(
          task.title,
          style: isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: task.description == null ? null : Text(task.description!),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(task.priority.name),
            PopupMenuButton<_TaskAction>(
              tooltip: 'Task actions',
              enabled: !_isUpdating,
              onSelected: (action) {
                if (action == _TaskAction.edit) {
                  _openEditSheet();
                } else {
                  _confirmDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: _TaskAction.edit, child: Text('Edit')),
                PopupMenuItem(value: _TaskAction.delete, child: Text('Delete')),
              ],
            ),
          ],
        ),
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

/// Creates a task, shown as a modal bottom sheet.
class _CreateTaskSheet extends ConsumerWidget {
  const _CreateTaskSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TaskFormSheet(
      heading: 'New task',
      submitLabel: 'Create task',
      initialTitle: '',
      initialDescription: null,
      initialPriority: TaskPriority.normal,
      onSubmit: (title, description, priority) => ref
          .read(tasksControllerProvider.notifier)
          .createTask(
            CreateTaskInput(
              title: title,
              description: description,
              priority: priority,
            ),
          ),
    );
  }
}

/// Edits an existing task, shown as a modal bottom sheet prefilled with its
/// current values.
class _EditTaskSheet extends ConsumerWidget {
  const _EditTaskSheet({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TaskFormSheet(
      heading: 'Edit task',
      submitLabel: 'Save changes',
      initialTitle: task.title,
      initialDescription: task.description,
      initialPriority: task.priority,
      onSubmit: (title, description, priority) => ref
          .read(tasksControllerProvider.notifier)
          .updateTask(
            task.id,
            UpdateTaskInput(
              title: title,
              description: description,
              priority: priority,
            ),
          ),
    );
  }
}

/// A responsive title/description/priority form, shared by [_CreateTaskSheet]
/// and [_EditTaskSheet], shown as the content of a modal bottom sheet.
class _TaskFormSheet extends ConsumerStatefulWidget {
  const _TaskFormSheet({
    required this.heading,
    required this.submitLabel,
    required this.initialTitle,
    required this.initialDescription,
    required this.initialPriority,
    required this.onSubmit,
  });

  final String heading;
  final String submitLabel;
  final String initialTitle;
  final String? initialDescription;
  final TaskPriority initialPriority;

  /// Submits the form's current values. Throws on failure, which the sheet
  /// surfaces inline without closing.
  final Future<void> Function(
    String title,
    String? description,
    TaskPriority priority,
  )
  onSubmit;

  @override
  ConsumerState<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<_TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  late final _descriptionController = TextEditingController(
    text: widget.initialDescription ?? '',
  );
  late TaskPriority _priority = widget.initialPriority;
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

    try {
      await widget.onSubmit(
        _titleController.text.trim(),
        description.isEmpty ? null : description,
        _priority,
      );
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
                    widget.heading,
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
                        : Text(widget.submitLabel),
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
