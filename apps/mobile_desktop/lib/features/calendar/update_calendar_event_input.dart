/// Payload for updating a calendar event via the NestJS
/// `PATCH /calendar-events/:id` endpoint.
///
/// The edit UI always submits the full current state of title, description,
/// start/end, all-day, and location, so unlike [CreateCalendarEventInput]
/// this always sends `description`/`location` (even when `null`) --
/// clearing an existing value must reach the backend as an explicit clear
/// rather than being silently dropped.
class UpdateCalendarEventInput {
  const UpdateCalendarEventInput({
    required this.title,
    this.description,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    this.location,
  });

  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final String? location;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'startAt': startAt.toUtc().toIso8601String(),
      'endAt': endAt.toUtc().toIso8601String(),
      'allDay': allDay,
      'location': location,
    };
  }
}
