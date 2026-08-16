import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'create_reminder_input.dart';
import 'reminder.dart';
import 'update_reminder_input.dart';

/// Fetches and mutates the authenticated user's reminders via the NestJS
/// backend.
///
/// Uses the shared [apiClientProvider] Dio client; never talks to Supabase's
/// `reminders` table directly.
class RemindersRepository {
  RemindersRepository(this._dio);

  final Dio _dio;

  Future<List<Reminder>> fetchReminders() async {
    final response = await _dio.get<List<dynamic>>('/reminders');
    final data = response.data ?? const [];
    return data
        .map((reminder) => Reminder.fromJson(reminder as Map<String, dynamic>))
        .toList();
  }

  Future<Reminder> createReminder(CreateReminderInput input) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/reminders',
      data: input.toJson(),
    );
    return Reminder.fromJson(response.data!);
  }

  Future<Reminder> updateReminder(
    String reminderId,
    UpdateReminderInput input,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/reminders/$reminderId',
      data: input.toJson(),
    );
    return Reminder.fromJson(response.data!);
  }

  /// The backend responds `204 No Content` on success, so there's no body
  /// to parse.
  Future<void> deleteReminder(String reminderId) async {
    await _dio.delete<void>('/reminders/$reminderId');
  }

  Future<Reminder> cancelReminder(String reminderId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/reminders/$reminderId/cancel',
    );
    return Reminder.fromJson(response.data!);
  }

  Future<Reminder> reactivateReminder(String reminderId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/reminders/$reminderId/reactivate',
    );
    return Reminder.fromJson(response.data!);
  }
}

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  return RemindersRepository(ref.watch(apiClientProvider));
});
