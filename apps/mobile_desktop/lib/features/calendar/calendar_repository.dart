import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'calendar_event.dart';
import 'create_calendar_event_input.dart';
import 'update_calendar_event_input.dart';

/// Fetches the authenticated user's calendar events via the NestJS backend.
///
/// Uses the shared [apiClientProvider] Dio client; never talks to Supabase's
/// `calendar_events` table directly.
class CalendarRepository {
  CalendarRepository(this._dio);

  final Dio _dio;

  /// Fetches the user's calendar events, ordered by `startAt` ascending.
  ///
  /// When [from]/[to] are provided, the backend returns events overlapping
  /// that range instead of the full list. Omit both for the current V0.1
  /// read-only view.
  Future<List<CalendarEvent>> fetchEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/calendar-events',
      queryParameters: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
    );
    final data = response.data ?? const [];
    return data
        .map((event) => CalendarEvent.fromJson(event as Map<String, dynamic>))
        .toList();
  }

  Future<CalendarEvent> createEvent(CreateCalendarEventInput input) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/calendar-events',
      data: input.toJson(),
    );
    return CalendarEvent.fromJson(response.data!);
  }

  Future<CalendarEvent> updateEvent(
    String eventId,
    UpdateCalendarEventInput input,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/calendar-events/$eventId',
      data: input.toJson(),
    );
    return CalendarEvent.fromJson(response.data!);
  }

  /// The backend responds `204 No Content` on success, so there's no body
  /// to parse.
  Future<void> deleteEvent(String eventId) async {
    await _dio.delete<void>('/calendar-events/$eventId');
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return CalendarRepository(ref.watch(apiClientProvider));
});
