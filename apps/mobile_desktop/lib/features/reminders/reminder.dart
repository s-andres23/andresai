/// A reminder's trigger type, matching the backend's `REMINDER_TRIGGER_TYPES`.
enum ReminderTriggerType { absolute, relative }

/// A reminder's lifecycle state, matching the backend's `REMINDER_STATUSES`.
enum ReminderStatus { pending, triggered, cancelled }

/// A reminder belonging to the authenticated user, as returned by the
/// NestJS `GET /reminders` endpoint.
class Reminder {
  const Reminder({
    required this.id,
    required this.userId,
    required this.taskId,
    required this.calendarEventId,
    required this.title,
    required this.triggerType,
    required this.offsetMinutes,
    required this.remindAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String? taskId;
  final String? calendarEventId;
  final String title;
  final ReminderTriggerType triggerType;
  final int? offsetMinutes;
  final DateTime remindAt;
  final ReminderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      userId: json['userId'] as String,
      taskId: json['taskId'] as String?,
      calendarEventId: json['calendarEventId'] as String?,
      title: json['title'] as String,
      triggerType: ReminderTriggerType.values.byName(
        json['triggerType'] as String,
      ),
      offsetMinutes: json['offsetMinutes'] as int?,
      remindAt: DateTime.parse(json['remindAt'] as String),
      status: ReminderStatus.values.byName(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
