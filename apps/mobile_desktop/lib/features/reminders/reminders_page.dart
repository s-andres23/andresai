import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/notifications/local_notification_service.dart';
import '../../core/notifications/notification_permission_state.dart';
import '../calendar/calendar_controller.dart';
import '../calendar/calendar_date_format.dart';
import '../calendar/calendar_event.dart';
import '../tasks/task.dart';
import '../tasks/tasks_controller.dart';
import 'create_reminder_input.dart';
import 'reminder.dart';
import 'reminders_controller.dart';
import 'update_reminder_input.dart';

/// Displays the authenticated user's reminders, and lets the user create,
/// edit, cancel, and delete them.
///
/// Also owns the V0.1 notification-permission UX: a short contextual
/// explanation shown once before the OS permission prompt, and a
/// non-blocking banner when notifications are off. Reminders always save
/// successfully in the backend regardless of this permission -- it only
/// affects whether a device-side alert accompanies them.
class RemindersPage extends ConsumerStatefulWidget {
  const RemindersPage({super.key});

  @override
  ConsumerState<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends ConsumerState<RemindersPage> {
  NotificationPermissionStatus? _permissionStatus;
  bool _hasShownPermissionExplanation = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissionStatus();
  }

  Future<void> _refreshPermissionStatus() async {
    final status = await ref
        .read(localNotificationServiceProvider)
        .getPermissionStatus();
    if (mounted) setState(() => _permissionStatus = status);
  }

  /// Shows a short AndresAI explanation before the OS permission prompt,
  /// the first time the user tries to use reminders while permission is
  /// undecided. Does nothing (no re-prompt) once a decision -- either way
  /// -- has already been made, or once this session has already asked.
  Future<void> _ensurePermissionRequested() async {
    if (_permissionStatus != NotificationPermissionStatus.notDetermined) {
      return;
    }
    if (_hasShownPermissionExplanation) return;
    _hasShownPermissionExplanation = true;

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable reminder notifications?'),
        content: const Text(
          'AndresAI can alert you on this device when a reminder is due. '
          'You can turn this off later in system settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (shouldRequest != true || !mounted) return;

    final status = await ref
        .read(localNotificationServiceProvider)
        .requestPermission();
    if (mounted) setState(() => _permissionStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    final remindersState = ref.watch(remindersControllerProvider);
    final notificationService = ref.read(localNotificationServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_permissionStatus == NotificationPermissionStatus.denied)
            _NotificationsDisabledBanner(
              canOpenSettings: notificationService.canOpenNotificationSettings,
              onOpenSettings: () async {
                await notificationService.openNotificationSettings();
                await _refreshPermissionStatus();
              },
            ),
          Expanded(
            child: switch (remindersState) {
              AsyncData(:final value) => _RemindersList(reminders: value),
              AsyncError(:final error) => _RemindersErrorView(
                message: error.toString(),
                onRetry: () =>
                    ref.read(remindersControllerProvider.notifier).refresh(),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _ensurePermissionRequested();
          if (!context.mounted) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const _CreateReminderSheet(),
          );
        },
        tooltip: 'Add reminder',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// A short, non-blocking banner shown when notification permission has been
/// denied, so the user understands why reminders won't alert them without
/// blocking reminder creation/editing itself.
class _NotificationsDisabledBanner extends StatelessWidget {
  const _NotificationsDisabledBanner({
    required this.canOpenSettings,
    required this.onOpenSettings,
  });

  final bool canOpenSettings;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.notifications_off_outlined,
              color: colors.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Notifications are off. Reminders still save, but you won't "
                'get a device alert.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            if (canOpenSettings)
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Settings'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemindersList extends StatelessWidget {
  const _RemindersList({required this.reminders});

  final List<Reminder> reminders;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const Center(child: Text('No reminders yet.'));
    }

    // The controller keeps the list ordered by remindAt ascending; it's
    // rendered in that order as-is.
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reminders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final reminder = reminders[index];
        // A stable per-reminder key so Flutter matches each row's Element
        // (and its local _isUpdating state) to the same reminder across
        // insertions, deletions, and reorders, instead of reusing whatever
        // State object previously occupied that list index.
        return _ReminderTile(key: ValueKey(reminder.id), reminder: reminder);
      },
      // Without this, ListView.separated only compares the old vs. new
      // widget at the *same* index: a keyed row whose reminder shifted to a
      // different index (e.g. after a delete, or an edit that changed its
      // sorted position) is discarded and rebuilt from scratch (losing its
      // _isUpdating state) rather than relocated. This lets Flutter find a
      // keyed row wherever it now lives and move its Element instead.
      findItemIndexCallback: (key) {
        final reminderId = (key as ValueKey<String>).value;
        final index = reminders.indexWhere(
          (reminder) => reminder.id == reminderId,
        );
        return index == -1 ? null : index;
      },
    );
  }
}

enum _ReminderAction { edit, cancel, delete }

class _ReminderTile extends ConsumerStatefulWidget {
  const _ReminderTile({super.key, required this.reminder});

  final Reminder reminder;

  @override
  ConsumerState<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends ConsumerState<_ReminderTile> {
  bool _isUpdating = false;

  void _openEditSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditReminderSheet(reminder: widget.reminder),
    );
  }

  Future<void> _cancelReminder() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    try {
      await ref
          .read(remindersControllerProvider.notifier)
          .cancelReminder(widget.reminder.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel reminder: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text(
          'Delete "${widget.reminder.title}"? This can\'t be undone.',
        ),
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
          .read(remindersControllerProvider.notifier)
          .deleteReminder(widget.reminder.id);
      // On success the reminder disappears from the list entirely once
      // `state` updates, so there's no tile left to reset `_isUpdating` on.
    } catch (error) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete reminder: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminder = widget.reminder;
    final isPending = reminder.status == ReminderStatus.pending;
    final dateTimeLabel =
        '${formatCalendarDate(reminder.remindAt)} · '
        '${formatCalendarTime(reminder.remindAt)}';

    String? parentLabel;
    if (reminder.taskId != null) {
      final tasks = ref.watch(tasksControllerProvider).value ?? const [];
      final task = _findTask(tasks, reminder.taskId);
      parentLabel = task != null ? 'Task: ${task.title}' : 'Linked task';
    } else if (reminder.calendarEventId != null) {
      final events = ref.watch(calendarControllerProvider).value ?? const [];
      final event = _findCalendarEvent(events, reminder.calendarEventId);
      final eventLabel = event != null ? event.title : 'Linked event';
      parentLabel = reminder.triggerType == ReminderTriggerType.relative
          ? '$eventLabel · ${_describeOffset(reminder.offsetMinutes ?? 0)}'
          : 'Event: $eventLabel';
    }

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
            : Icon(
                isPending
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
              ),
        title: Text(
          reminder.title,
          style: reminder.status == ReminderStatus.cancelled
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dateTimeLabel),
            if (parentLabel != null) Text(parentLabel),
            Text(_statusLabel(reminder.status)),
          ],
        ),
        trailing: PopupMenuButton<_ReminderAction>(
          tooltip: 'Reminder actions',
          enabled: !_isUpdating,
          onSelected: (action) {
            switch (action) {
              case _ReminderAction.edit:
                _openEditSheet();
              case _ReminderAction.cancel:
                _cancelReminder();
              case _ReminderAction.delete:
                _confirmDelete();
            }
          },
          // Triggered/cancelled reminders can't be edited or cancelled --
          // the backend rejects both -- so those actions are hidden rather
          // than shown and left to fail.
          itemBuilder: (context) => [
            if (isPending)
              const PopupMenuItem(
                value: _ReminderAction.edit,
                child: Text('Edit'),
              ),
            if (isPending)
              const PopupMenuItem(
                value: _ReminderAction.cancel,
                child: Text('Cancel'),
              ),
            const PopupMenuItem(
              value: _ReminderAction.delete,
              child: Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemindersErrorView extends StatelessWidget {
  const _RemindersErrorView({required this.message, required this.onRetry});

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
              'Failed to load reminders',
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

/// Where a reminder being created is linked to, if anywhere.
///
/// Relative Task reminders are intentionally unsupported by the backend (no
/// safe timezone model yet), so [task] only ever pairs with an absolute
/// reminder -- there is no relative toggle shown for it.
enum _LinkType { none, task, calendarEvent }

/// Preset offsets for a relative Calendar reminder, shown as create-time
/// choices per the V0.1 UX spec.
const List<({String label, int minutes})> _offsetPresets = [
  (label: '10 minutes before', minutes: -10),
  (label: '30 minutes before', minutes: -30),
  (label: '1 hour before', minutes: -60),
  (label: '1 day before', minutes: -1440),
];

/// A human-readable description of [minutes], preferring a known preset
/// label and falling back to a generic description for any other value
/// (e.g. one created outside this UI).
String _describeOffset(int minutes) {
  for (final preset in _offsetPresets) {
    if (preset.minutes == minutes) return preset.label;
  }
  final absMinutes = minutes.abs();
  final suffix = minutes < 0 ? 'before' : 'after';
  return '$absMinutes minute${absMinutes == 1 ? '' : 's'} $suffix';
}

String _statusLabel(ReminderStatus status) => switch (status) {
  ReminderStatus.pending => 'Pending',
  ReminderStatus.triggered => 'Triggered',
  ReminderStatus.cancelled => 'Cancelled',
};

Task? _findTask(List<Task> tasks, String? id) {
  if (id == null) return null;
  for (final task in tasks) {
    if (task.id == id) return task;
  }
  return null;
}

CalendarEvent? _findCalendarEvent(List<CalendarEvent> events, String? id) {
  if (id == null) return null;
  for (final event in events) {
    if (event.id == id) return event;
  }
  return null;
}

/// Creates a reminder, shown as a responsive modal bottom sheet.
class _CreateReminderSheet extends ConsumerWidget {
  const _CreateReminderSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CreateReminderFormSheet(
      onSubmit: (input) =>
          ref.read(remindersControllerProvider.notifier).createReminder(input),
    );
  }
}

/// A responsive form for creating a reminder, shown as the content of a
/// modal bottom sheet.
///
/// Supports three creation modes, selected via [_LinkType]: a standalone
/// absolute reminder, a task-linked absolute reminder, and a Calendar-linked
/// reminder that is either absolute or relative to the event's start. This
/// isn't shared with the edit form ([_EditReminderFormSheet]) because a
/// reminder's parent/trigger type is fixed after creation -- editing only
/// ever touches title plus (depending on trigger type) remindAt or
/// offsetMinutes.
class _CreateReminderFormSheet extends ConsumerStatefulWidget {
  const _CreateReminderFormSheet({required this.onSubmit});

  final Future<void> Function(CreateReminderInput input) onSubmit;

  @override
  ConsumerState<_CreateReminderFormSheet> createState() =>
      _CreateReminderFormSheetState();
}

class _CreateReminderFormSheetState
    extends ConsumerState<_CreateReminderFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  _LinkType _linkType = _LinkType.none;
  String? _selectedTaskId;
  String? _selectedCalendarEventId;
  bool _isRelative = false;
  int _offsetMinutes = _offsetPresets.first.minutes;
  DateTime _remindAt = DateTime.now().add(const Duration(hours: 1));

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<CalendarEvent> events) async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    String? taskId;
    String? calendarEventId;
    var triggerType = ReminderTriggerType.absolute;
    int? offsetMinutes;
    DateTime remindAt;

    switch (_linkType) {
      case _LinkType.none:
        remindAt = _remindAt;
      case _LinkType.task:
        if (_selectedTaskId == null) {
          setState(() => _submitError = 'Select a task');
          return;
        }
        taskId = _selectedTaskId;
        remindAt = _remindAt;
      case _LinkType.calendarEvent:
        if (_selectedCalendarEventId == null) {
          setState(() => _submitError = 'Select an event');
          return;
        }
        calendarEventId = _selectedCalendarEventId;
        if (_isRelative) {
          final event = _findCalendarEvent(events, _selectedCalendarEventId);
          if (event == null) {
            setState(() => _submitError = 'Select an event');
            return;
          }
          triggerType = ReminderTriggerType.relative;
          offsetMinutes = _offsetMinutes;
          // A client-side preview only -- the backend recalculates remindAt
          // authoritatively from the event's persisted startAt.
          remindAt = event.startAt.add(Duration(minutes: _offsetMinutes));
        } else {
          remindAt = _remindAt;
        }
    }

    if (triggerType == ReminderTriggerType.absolute &&
        !remindAt.isAfter(DateTime.now())) {
      setState(() => _submitError = 'Reminder time must be in the future');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.onSubmit(
        CreateReminderInput(
          title: title,
          taskId: taskId,
          calendarEventId: calendarEventId,
          triggerType: triggerType,
          offsetMinutes: offsetMinutes,
          remindAt: remindAt,
        ),
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
    // Reuses the Tasks/Calendar controllers already loaded elsewhere in the
    // app (both tabs are built by HomeShell's IndexedStack) instead of
    // duplicating their fetch logic here.
    final tasks = ref.watch(tasksControllerProvider).value ?? const [];
    final events = ref.watch(calendarControllerProvider).value ?? const [];
    final selectedEvent = _findCalendarEvent(events, _selectedCalendarEventId);
    final showAbsolutePicker =
        _linkType != _LinkType.calendarEvent || !_isRelative;

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
                    'New reminder',
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
                        CreateReminderInput.validateTitle(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_LinkType>(
                    segments: const [
                      ButtonSegment(value: _LinkType.none, label: Text('None')),
                      ButtonSegment(value: _LinkType.task, label: Text('Task')),
                      ButtonSegment(
                        value: _LinkType.calendarEvent,
                        label: Text('Event'),
                      ),
                    ],
                    selected: {_linkType},
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (selection) => setState(() {
                            _linkType = selection.first;
                            _submitError = null;
                          }),
                  ),
                  if (_linkType == _LinkType.task) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('reminder-task-dropdown'),
                      decoration: const InputDecoration(labelText: 'Task'),
                      isExpanded: true,
                      initialValue:
                          tasks.any((task) => task.id == _selectedTaskId)
                          ? _selectedTaskId
                          : null,
                      items: [
                        for (final task in tasks)
                          DropdownMenuItem(
                            value: task.id,
                            child: Text(
                              task.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(() => _selectedTaskId = value),
                    ),
                  ],
                  if (_linkType == _LinkType.calendarEvent) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('reminder-event-dropdown'),
                      decoration: const InputDecoration(
                        labelText: 'Calendar event',
                      ),
                      isExpanded: true,
                      initialValue:
                          events.any(
                            (event) => event.id == _selectedCalendarEventId,
                          )
                          ? _selectedCalendarEventId
                          : null,
                      items: [
                        for (final event in events)
                          DropdownMenuItem(
                            value: event.id,
                            child: Text(
                              '${event.title} · '
                              '${formatCalendarDate(event.startAt)} '
                              '${formatCalendarTime(event.startAt)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(
                              () => _selectedCalendarEventId = value,
                            ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Relative to event start'),
                      value: _isRelative,
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(() => _isRelative = value),
                    ),
                  ],
                  if (showAbsolutePicker) ...[
                    const SizedBox(height: 12),
                    _ReminderDateTimeField(
                      label: 'Remind me at',
                      value: _remindAt,
                      enabled: !_isSubmitting,
                      onChanged: (value) => setState(() => _remindAt = value),
                    ),
                  ],
                  if (_linkType == _LinkType.calendarEvent && _isRelative) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: const ValueKey('reminder-offset-dropdown'),
                      decoration: const InputDecoration(labelText: 'Offset'),
                      initialValue: _offsetMinutes,
                      items: [
                        for (final preset in _offsetPresets)
                          DropdownMenuItem(
                            value: preset.minutes,
                            child: Text(preset.label),
                          ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(() => _offsetMinutes = value!),
                    ),
                    if (selectedEvent != null) ...[
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final preview = selectedEvent.startAt.add(
                            Duration(minutes: _offsetMinutes),
                          );
                          return Text(
                            '${_describeOffset(_offsetMinutes)} — '
                            '${formatCalendarDate(preview)} '
                            '${formatCalendarTime(preview)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ],
                  ],
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
                    onPressed: _isSubmitting ? null : () => _submit(events),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create reminder'),
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

/// Edits an existing *pending* reminder, shown as a modal bottom sheet.
///
/// Only fields the backend allows changing are shown, and a reminder's
/// parent/trigger type never changes after creation, so unlike the create
/// sheet there is no [_LinkType] selector here.
class _EditReminderSheet extends ConsumerWidget {
  const _EditReminderSheet({required this.reminder});

  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _EditReminderFormSheet(
      reminder: reminder,
      onSubmit: (input) => ref
          .read(remindersControllerProvider.notifier)
          .updateReminder(reminder.id, input),
    );
  }
}

class _EditReminderFormSheet extends ConsumerStatefulWidget {
  const _EditReminderFormSheet({
    required this.reminder,
    required this.onSubmit,
  });

  final Reminder reminder;
  final Future<void> Function(UpdateReminderInput input) onSubmit;

  @override
  ConsumerState<_EditReminderFormSheet> createState() =>
      _EditReminderFormSheetState();
}

class _EditReminderFormSheetState
    extends ConsumerState<_EditReminderFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.reminder.title,
  );

  late DateTime _remindAt = widget.reminder.remindAt.toLocal();
  late int _offsetMinutes = widget.reminder.offsetMinutes ?? -10;

  bool _isSubmitting = false;
  String? _submitError;

  bool get _isRelative =>
      widget.reminder.triggerType == ReminderTriggerType.relative;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    if (!_isRelative && !_remindAt.isAfter(DateTime.now())) {
      setState(() => _submitError = 'Reminder time must be in the future');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final title = _titleController.text.trim();

    try {
      await widget.onSubmit(
        _isRelative
            ? UpdateReminderInput(title: title, offsetMinutes: _offsetMinutes)
            : UpdateReminderInput(title: title, remindAt: _remindAt),
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
    // The reminder may have been created with an offset that doesn't match
    // any current preset (e.g. from elsewhere); include it so the dropdown
    // always has a valid selected value.
    final offsetItems = [
      for (final preset in _offsetPresets) preset.minutes,
      if (!_offsetPresets.any((preset) => preset.minutes == _offsetMinutes))
        _offsetMinutes,
    ];

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
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
                    'Edit reminder',
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
                        CreateReminderInput.validateTitle(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  if (_isRelative)
                    DropdownButtonFormField<int>(
                      key: const ValueKey('reminder-edit-offset-dropdown'),
                      decoration: const InputDecoration(labelText: 'Offset'),
                      initialValue: _offsetMinutes,
                      items: [
                        for (final minutes in offsetItems)
                          DropdownMenuItem(
                            value: minutes,
                            child: Text(_describeOffset(minutes)),
                          ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) => setState(() => _offsetMinutes = value!),
                    )
                  else
                    _ReminderDateTimeField(
                      label: 'Remind me at',
                      value: _remindAt,
                      enabled: !_isSubmitting,
                      onChanged: (value) => setState(() => _remindAt = value),
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
                        : const Text('Save changes'),
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

/// A labeled date+time picker field, mirroring the Calendar feature's
/// `_DateTimeField` -- kept as a private per-feature copy since reminders
/// always need a full date+time (no all-day mode to toggle off the time
/// portion).
class _ReminderDateTimeField extends StatelessWidget {
  const _ReminderDateTimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    onChanged(
      DateTime(picked.year, picked.month, picked.day, value.hour, value.minute),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (picked == null) return;
    onChanged(
      DateTime(value.year, value.month, value.day, picked.hour, picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: enabled ? () => _pickDate(context) : null,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(formatCalendarDate(value)),
              ),
            ),
          ),
          TextButton(
            onPressed: enabled ? () => _pickTime(context) : null,
            child: Text(formatCalendarTime(value)),
          ),
        ],
      ),
    );
  }
}
