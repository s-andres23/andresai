import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'calendar_controller.dart';
import 'calendar_date_format.dart';
import 'calendar_event.dart';
import 'create_calendar_event_input.dart';

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
      itemBuilder: (context, index) =>
          _EventTile(key: ValueKey(events[index].id), event: events[index]),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final date = formatCalendarDate(event.startAt);
    final timeRange = event.allDay
        ? 'All day'
        : '${formatCalendarTime(event.startAt)} – ${formatCalendarTime(event.endAt)}';
    final location = event.location;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.event),
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
///
/// Follows the same responsive layout as the Tasks feature's create/edit
/// sheet: scrollable, SafeArea-aware, keyboard-avoiding, and width-capped on
/// desktop.
class _CreateEventSheet extends ConsumerStatefulWidget {
  const _CreateEventSheet();

  @override
  ConsumerState<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends ConsumerState<_CreateEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  bool _allDay = false;
  late DateTime _startAt = DateTime.now();
  late DateTime _endAt = _startAt.add(const Duration(hours: 1));
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
    final input = CreateCalendarEventInput(
      title: _titleController.text.trim(),
      description: description.isEmpty ? null : description,
      startAt: effectiveStartAt,
      endAt: effectiveEndAt,
      allDay: _allDay,
      location: location.isEmpty ? null : location,
    );

    try {
      await ref.read(calendarControllerProvider.notifier).createEvent(input);
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
                    'New event',
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
                        : const Text('Create event'),
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
