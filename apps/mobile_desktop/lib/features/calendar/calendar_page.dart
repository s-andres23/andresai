import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import 'calendar_controller.dart';
import 'calendar_event.dart';

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
    final date = _formatDate(event.startAt);
    final timeRange = event.allDay
        ? 'All day'
        : '${_formatTime(event.startAt)} – ${_formatTime(event.endAt)}';
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

/// Formats [dateTime] (converted to local time) as `YYYY-MM-DD`.
String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Formats [dateTime] (converted to local time) as 24-hour `HH:mm`.
String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
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
