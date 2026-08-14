/// A calendar event belonging to the authenticated user, as returned by the
/// NestJS `GET /calendar-events` endpoint.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.location,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final String? location;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      allDay: json['allDay'] as bool,
      location: json['location'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
