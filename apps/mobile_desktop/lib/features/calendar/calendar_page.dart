import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'calendar_controller.dart';
import 'calendar_date_format.dart';
import 'calendar_event.dart';
import 'create_calendar_event_input.dart';
import 'update_calendar_event_input.dart';

/// Displays the authenticated user's calendar events, ordered by start time.
///
/// Read-only for V0.1: this is a simple list, not yet a graphical
/// month/week calendar.
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendarState = ref.watch(calendarControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: switch (calendarState) {
        AsyncData(:final value) => _CalendarEventsList(events: value),
        AsyncError(:final error) => _CalendarErrorView(
          message: error.toString(),
          onRetry: () =>
              ref.read(calendarControllerProvider.notifier).refresh(),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const _CreateEventSheet(),
        ),
        tooltip: 'Add event',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CalendarEventsList extends StatelessWidget {
  const _CalendarEventsList({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('No events yet.'));
    }

    // The backend already orders results by start_at ascending; the list is
    // rendered in that order as-is.
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        // A stable per-event key so Flutter matches each row's Element (and
        // its local _isUpdating state) to the same event across insertions,
        // deletions, and reorders, instead of reusing whatever State object
        // previously occupied that list index.
        return _EventTile(key: ValueKey(event.id), event: event);
      },
      // Without this, ListView.separated only compares the old vs. new
      // widget at the *same* index: a keyed row whose event shifted to a
      // different index (e.g. after a delete, or an edit that changed its
      // sorted position) is discarded and rebuilt from scratch (losing its
      // _isUpdating state) rather than relocated. This lets Flutter find a
      // keyed row wherever it now lives and move its Element instead.
      findItemIndexCallback: (key) {
        final eventId = (key as ValueKey<String>).value;
        final index = events.indexWhere((event) => event.id == eventId);
        return index == -1 ? null : index;
      },
    );
  }
}

enum _EventAction { edit, delete }

class _EventTile extends ConsumerStatefulWidget {
  const _EventTile({super.key, required this.event});

  final CalendarEvent event;

  @override
  ConsumerState<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends ConsumerState<_EventTile> {
  bool _isUpdating = false;

  void _openEditSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditEventSheet(event: widget.event),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text('Delete "${widget.event.title}"? This can\'t be undone.'),
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
          .read(calendarControllerProvider.notifier)
          .deleteEvent(widget.event.id);
      // On success the event disappears from the list entirely once `state`
      // updates, so there's no tile left to reset `_isUpdating` on.
    } catch (error) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete event: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final date = formatCalendarDate(event.startAt);
    final timeRange = event.allDay
        ? 'All day'
        : '${formatCalendarTime(event.startAt)} – ${formatCalendarTime(event.endAt)}';
    final location = event.location;

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
            : const Icon(Icons.event),
        title: Text(event.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$date · $timeRange'),
            if (event.description != null) Text(event.description!),
            if (location != null && location.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined, size: 16),
                  const SizedBox(width: 4),
                  Flexible(child: Text(location)),
                ],
              ),
          ],
        ),
        trailing: PopupMenuButton<_EventAction>(
          tooltip: 'Event actions',
          enabled: !_isUpdating,
          onSelected: (action) {
            if (action == _EventAction.edit) {
              _openEditSheet();
            } else {
              _confirmDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: _EventAction.edit, child: Text('Edit')),
            PopupMenuItem(value: _EventAction.delete, child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _CalendarErrorView extends StatelessWidget {
  const _CalendarErrorView({required this.message, required this.onRetry});

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
              'Failed to load calendar events',
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

/// Computes the new end value when a create-event form's start changes,
/// preserving the previous start-to-end duration relative to [newStart].
///
/// Falls back to a 1-hour duration if the previous interval
/// ([previousEnd] - [previousStart]) is zero, negative, or otherwise
/// unusable, rather than propagating a broken gap onto the new start.
DateTime computeEndAfterStartChange({
  required DateTime previousStart,
  required DateTime previousEnd,
  required DateTime newStart,
}) {
  final previousDuration = previousEnd.difference(previousStart);
  final duration = previousDuration > Duration.zero
      ? previousDuration
      : const Duration(hours: 1);
  return newStart.add(duration);
}

/// Creates a calendar event, shown as a responsive modal bottom sheet.
class _CreateEventSheet extends ConsumerWidget {
  const _CreateEventSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return _EventFormSheet(
      heading: 'New event',
      submitLabel: 'Create event',
      initialTitle: '',
      initialDescription: null,
      initialStartAt: now,
      initialEndAt: now.add(const Duration(hours: 1)),
      initialAllDay: false,
      initialLocation: null,
      onSubmit: (title, description, startAt, endAt, allDay, location) => ref
          .read(calendarControllerProvider.notifier)
          .createEvent(
            CreateCalendarEventInput(
              title: title,
              description: description,
              startAt: startAt,
              endAt: endAt,
              allDay: allDay,
              location: location,
            ),
          ),
    );
  }
}

/// Edits an existing calendar event, shown as a modal bottom sheet prefilled
/// with its current values.
class _EditEventSheet extends ConsumerWidget {
  const _EditEventSheet({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The backend stores an all-day event's end as an *exclusive* midnight
    // (the day after the last selected day), but the form's end picker
    // shows an *inclusive* last day -- undo that offset when prefilling, or
    // saving without touching the end field would push it out by a day.
    final initialEndAt = event.allDay
        ? event.endAt.subtract(const Duration(days: 1))
        : event.endAt;

    return _EventFormSheet(
      heading: 'Edit event',
      submitLabel: 'Save changes',
      initialTitle: event.title,
      initialDescription: event.description,
      initialStartAt: event.startAt,
      initialEndAt: initialEndAt,
      initialAllDay: event.allDay,
      initialLocation: event.location,
      onSubmit: (title, description, startAt, endAt, allDay, location) => ref
          .read(calendarControllerProvider.notifier)
          .updateEvent(
            event.id,
            UpdateCalendarEventInput(
              title: title,
              description: description,
              startAt: startAt,
              endAt: endAt,
              allDay: allDay,
              location: location,
            ),
          ),
    );
  }
}

/// A responsive title/description/start/end/all-day/location form, shared
/// by [_CreateEventSheet] and [_EditEventSheet], shown as the content of a
/// modal bottom sheet.
///
/// Follows the same responsive layout as the Tasks feature's create/edit
/// sheet: scrollable, SafeArea-aware, keyboard-avoiding, and width-capped on
/// desktop.
class _EventFormSheet extends ConsumerStatefulWidget {
  const _EventFormSheet({
    required this.heading,
    required this.submitLabel,
    required this.initialTitle,
    required this.initialDescription,
    required this.initialStartAt,
    required this.initialEndAt,
    required this.initialAllDay,
    required this.initialLocation,
    required this.onSubmit,
  });

  final String heading;
  final String submitLabel;
  final String initialTitle;
  final String? initialDescription;
  final DateTime initialStartAt;
  final DateTime initialEndAt;
  final bool initialAllDay;
  final String? initialLocation;

  /// Submits the form's current (already all-day-adjusted) values. Throws
  /// on failure, which the sheet surfaces inline without closing.
  final Future<void> Function(
    String title,
    String? description,
    DateTime startAt,
    DateTime endAt,
    bool allDay,
    String? location,
  )
  onSubmit;

  @override
  ConsumerState<_EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends ConsumerState<_EventFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  late final _descriptionController = TextEditingController(
    text: widget.initialDescription ?? '',
  );
  late final _locationController = TextEditingController(
    text: widget.initialLocation ?? '',
  );

  late bool _allDay = widget.initialAllDay;
  late DateTime _startAt = widget.initialStartAt;
  late DateTime _endAt = widget.initialEndAt;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// Applies a new start value, shifting [_endAt] so the previous
  /// start-to-end duration is preserved relative to the new start.
  void _onStartChanged(DateTime newStart) {
    final newEnd = computeEndAfterStartChange(
      previousStart: _startAt,
      previousEnd: _endAt,
      newStart: newStart,
    );

    setState(() {
      _startAt = newStart;
      _endAt = newEnd;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    // All-day events are defined as spanning full local days: startAt is
    // local midnight of the selected start date, and endAt is local
    // midnight of the day *after* the selected end date (an exclusive
    // end), so a single-day all-day event still spans exactly 24 hours and
    // a multi-day range is inclusive of both picked dates.
    final DateTime effectiveStartAt;
    final DateTime effectiveEndAt;
    if (_allDay) {
      effectiveStartAt = DateTime(_startAt.year, _startAt.month, _startAt.day);
      effectiveEndAt = DateTime(
        _endAt.year,
        _endAt.month,
        _endAt.day,
      ).add(const Duration(days: 1));
    } else {
      effectiveStartAt = _startAt;
      effectiveEndAt = _endAt;
    }

    final intervalError = CreateCalendarEventInput.validateInterval(
      effectiveStartAt,
      effectiveEndAt,
    );
    if (intervalError != null) {
      setState(() => _submitError = intervalError);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();

    try {
      await widget.onSubmit(
        _titleController.text.trim(),
        description.isEmpty ? null : description,
        effectiveStartAt,
        effectiveEndAt,
        _allDay,
        location.isEmpty ? null : location,
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
                        CreateCalendarEventInput.validateTitle(value ?? ''),
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
                        CreateCalendarEventInput.validateDescription(
                          value ?? '',
                        ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All day'),
                    value: _allDay,
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _allDay = value),
                  ),
                  const SizedBox(height: 4),
                  _DateTimeField(
                    label: 'Start',
                    value: _startAt,
                    showTime: !_allDay,
                    enabled: !_isSubmitting,
                    onChanged: _onStartChanged,
                  ),
                  const SizedBox(height: 12),
                  _DateTimeField(
                    label: 'End',
                    value: _endAt,
                    showTime: !_allDay,
                    enabled: !_isSubmitting,
                    onChanged: (value) => setState(() => _endAt = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location (optional)',
                    ),
                    enabled: !_isSubmitting,
                    validator: (value) =>
                        CreateCalendarEventInput.validateLocation(value ?? ''),
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

/// A labeled date (and, unless [showTime] is false, time) picker field.
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.showTime,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool showTime;
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
          if (showTime)
            TextButton(
              onPressed: enabled ? () => _pickTime(context) : null,
              child: Text(formatCalendarTime(value)),
            ),
        ],
      ),
    );
  }
}
