import 'reminder.dart';

/// Maximum length accepted by the backend's `CreateReminderDto`.
const _maxTitleLength = 200;

/// Payload for creating a reminder via the NestJS `POST /reminders`
/// endpoint.
///
/// Kept separate from [Reminder] because the request shape (what the client
/// may send) and the response shape (what the server returns, including
/// server-assigned fields like `id`) are different contracts.
class CreateReminderInput {
  const CreateReminderInput({
    required this.title,
    this.taskId,
    this.calendarEventId,
    required this.triggerType,
    this.offsetMinutes,
    required this.remindAt,
  });

  final String title;
  final String? taskId;
  final String? calendarEventId;
  final ReminderTriggerType triggerType;
  final int? offsetMinutes;

  /// For an absolute reminder this is the authoritative trigger instant.
  ///
  /// For a relative Calendar reminder the backend recalculates `remindAt`
  /// itself from the linked event's `startAt` and [offsetMinutes] -- this
  /// value is still required by the DTO contract, but is only a client-side
  /// preview, never treated as authoritative.
  final DateTime remindAt;

  /// Returns a user-facing error for [title], or `null` if it's valid.
  static String? validateTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Title is required';
    if (trimmed.length > _maxTitleLength) {
      return 'Title must be $_maxTitleLength characters or fewer';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (taskId != null) 'taskId': taskId,
      if (calendarEventId != null) 'calendarEventId': calendarEventId,
      'triggerType': triggerType.name,
      if (offsetMinutes != null) 'offsetMinutes': offsetMinutes,
      'remindAt': remindAt.toUtc().toIso8601String(),
    };
  }
}
