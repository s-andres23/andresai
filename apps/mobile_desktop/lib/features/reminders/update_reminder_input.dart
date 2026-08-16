import 'create_reminder_input.dart';

/// Payload for updating a reminder via the NestJS `PATCH /reminders/:id`
/// endpoint.
///
/// The backend only allows editing a *pending* reminder, and the edit UI
/// never changes a reminder's parent (task/calendar event) or trigger type
/// once created, so unlike [CreateReminderInput] this never sends
/// `taskId`/`calendarEventId`/`triggerType` -- the backend keeps those at
/// their existing values when a field is omitted from the request body.
class UpdateReminderInput {
  const UpdateReminderInput({
    required this.title,
    this.offsetMinutes,
    this.remindAt,
  });

  final String title;

  /// Set only when editing a relative reminder's offset.
  final int? offsetMinutes;

  /// Set only when editing an absolute reminder's trigger instant.
  final DateTime? remindAt;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (offsetMinutes != null) 'offsetMinutes': offsetMinutes,
      if (remindAt != null) 'remindAt': remindAt!.toUtc().toIso8601String(),
    };
  }
}
