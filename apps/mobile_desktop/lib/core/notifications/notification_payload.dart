import 'dart:convert';

/// Data carried by a scheduled reminder notification, round-tripped through
/// the notification plugin's opaque `payload` string so a tap (or a
/// reconciliation pass) can trace a local notification back to the
/// reminder -- and its parent, if any -- that it belongs to.
///
/// JSON-encoded rather than a bespoke delimited format so it stays easy to
/// extend later (e.g. adding fields for future notification types) without
/// breaking the shape of payloads already scheduled on-device.
class NotificationPayload {
  const NotificationPayload({
    required this.reminderId,
    this.taskId,
    this.calendarEventId,
  });

  final String reminderId;
  final String? taskId;
  final String? calendarEventId;

  String encode() => jsonEncode({
    'reminderId': reminderId,
    if (taskId != null) 'taskId': taskId,
    if (calendarEventId != null) 'calendarEventId': calendarEventId,
  });

  /// Returns `null` for a missing, empty, or malformed payload rather than
  /// throwing -- a tap on (or reconciliation of) an unrecognized
  /// notification should be treated as a no-op, not a crash.
  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      final reminderId = json['reminderId'];
      if (reminderId is! String || reminderId.isEmpty) return null;

      return NotificationPayload(
        reminderId: reminderId,
        taskId: json['taskId'] as String?,
        calendarEventId: json['calendarEventId'] as String?,
      );
    } on FormatException {
      return null;
    }
  }
}
