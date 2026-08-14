/// Maximum lengths accepted by the backend's `CreateCalendarEventDto`.
const _maxTitleLength = 200;
const _maxDescriptionLength = 2000;
const _maxLocationLength = 200;

/// Payload for creating a calendar event via the NestJS
/// `POST /calendar-events` endpoint.
///
/// Kept separate from [CalendarEvent] because the request shape (what the
/// client may send) and the response shape (what the server returns,
/// including server-assigned fields like `id`) are different contracts.
class CreateCalendarEventInput {
  const CreateCalendarEventInput({
    required this.title,
    this.description,
    required this.startAt,
    required this.endAt,
    this.allDay = false,
    this.location,
  });

  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final String? location;

  /// Returns a user-facing error for [title], or `null` if it's valid.
  static String? validateTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Title is required';
    if (trimmed.length > _maxTitleLength) {
      return 'Title must be $_maxTitleLength characters or fewer';
    }
    return null;
  }

  /// Returns a user-facing error for [description], or `null` if it's valid.
  static String? validateDescription(String description) {
    if (description.length > _maxDescriptionLength) {
      return 'Description must be $_maxDescriptionLength characters or fewer';
    }
    return null;
  }

  /// Returns a user-facing error for [location], or `null` if it's valid.
  static String? validateLocation(String location) {
    if (location.length > _maxLocationLength) {
      return 'Location must be $_maxLocationLength characters or fewer';
    }
    return null;
  }

  /// Returns a user-facing error when [endAt] is before [startAt], or `null`
  /// if the interval is valid.
  static String? validateInterval(DateTime startAt, DateTime endAt) {
    if (endAt.isBefore(startAt)) {
      return 'End must not be before start';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      if (description != null) 'description': description,
      'startAt': startAt.toUtc().toIso8601String(),
      'endAt': endAt.toUtc().toIso8601String(),
      'allDay': allDay,
      if (location != null) 'location': location,
    };
  }
}
