import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/reminders/create_reminder_input.dart';
import 'package:mobile_desktop/features/reminders/reminder.dart';
import 'package:mobile_desktop/features/reminders/reminders_repository.dart';
import 'package:mobile_desktop/features/reminders/update_reminder_input.dart';

/// Returns a fixed JSON body for every request, without performing any real
/// network I/O.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final String body;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Returns an empty `204 No Content` response for every request, matching
/// what the backend's `DELETE /reminders/:id` endpoint responds with.
class _NoContentAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _row({
  String id = 'reminder-1',
  String? taskId,
  String? calendarEventId,
  String title = 'Call insurance',
  String triggerType = 'absolute',
  int? offsetMinutes,
  String remindAt = '2026-08-18T18:00:00.000Z',
  String status = 'pending',
}) {
  return {
    'id': id,
    'userId': 'user-1',
    'taskId': taskId,
    'calendarEventId': calendarEventId,
    'title': title,
    'triggerType': triggerType,
    'offsetMinutes': offsetMinutes,
    'remindAt': remindAt,
    'status': status,
    'createdAt': '2026-08-14T00:00:00.000Z',
    'updatedAt': '2026-08-14T00:00:00.000Z',
  };
}

void main() {
  test('fetchReminders calls GET /reminders and parses the response', () async {
    final adapter = _StubAdapter(jsonEncode([_row()]));
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = RemindersRepository(dio);

    final reminders = await repository.fetchReminders();

    expect(adapter.lastOptions!.path, '/reminders');
    expect(adapter.lastOptions!.method, 'GET');
    expect(reminders, hasLength(1));
    expect(reminders.single.title, 'Call insurance');
    expect(reminders.single.status, ReminderStatus.pending);
  });

  test('fetchReminders returns an empty list for an empty response', () async {
    final dio = Dio()..httpClientAdapter = _StubAdapter(jsonEncode([]));
    final repository = RemindersRepository(dio);

    final reminders = await repository.fetchReminders();

    expect(reminders, isEmpty);
  });

  test(
    'createReminder posts the payload and parses the created reminder',
    () async {
      final adapter = _StubAdapter(
        jsonEncode(
          _row(
            id: 'reminder-2',
            calendarEventId: 'event-1',
            title: 'Team sync',
            triggerType: 'relative',
            offsetMinutes: -15,
            remindAt: '2026-08-20T08:45:00.000Z',
          ),
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = RemindersRepository(dio);

      final reminder = await repository.createReminder(
        CreateReminderInput(
          title: 'Team sync',
          calendarEventId: 'event-1',
          triggerType: ReminderTriggerType.relative,
          offsetMinutes: -15,
          remindAt: DateTime.utc(2026, 8, 20, 8, 45),
        ),
      );

      expect(adapter.lastOptions!.path, '/reminders');
      expect(adapter.lastOptions!.method, 'POST');
      expect(adapter.lastOptions!.data, {
        'title': 'Team sync',
        'calendarEventId': 'event-1',
        'triggerType': 'relative',
        'offsetMinutes': -15,
        'remindAt': '2026-08-20T08:45:00.000Z',
      });
      expect(reminder.id, 'reminder-2');
      expect(reminder.triggerType, ReminderTriggerType.relative);
    },
  );

  test('updateReminder patches /reminders/:id with the payload and parses the '
      'response', () async {
    final adapter = _StubAdapter(
      jsonEncode(_row(title: 'Call insurance (renamed)')),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = RemindersRepository(dio);

    final reminder = await repository.updateReminder(
      'reminder-1',
      const UpdateReminderInput(title: 'Call insurance (renamed)'),
    );

    expect(adapter.lastOptions!.path, '/reminders/reminder-1');
    expect(adapter.lastOptions!.method, 'PATCH');
    expect(adapter.lastOptions!.data, {'title': 'Call insurance (renamed)'});
    expect(reminder.title, 'Call insurance (renamed)');
  });

  test('deleteReminder sends DELETE /reminders/:id', () async {
    final adapter = _NoContentAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = RemindersRepository(dio);

    await repository.deleteReminder('reminder-1');

    expect(adapter.lastOptions!.path, '/reminders/reminder-1');
    expect(adapter.lastOptions!.method, 'DELETE');
  });

  test(
    'cancelReminder posts to /reminders/:id/cancel and parses the response',
    () async {
      final adapter = _StubAdapter(jsonEncode(_row(status: 'cancelled')));
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = RemindersRepository(dio);

      final reminder = await repository.cancelReminder('reminder-1');

      expect(adapter.lastOptions!.path, '/reminders/reminder-1/cancel');
      expect(adapter.lastOptions!.method, 'POST');
      expect(reminder.status, ReminderStatus.cancelled);
    },
  );

  test('reactivateReminder posts to /reminders/:id/reactivate and parses the '
      'response', () async {
    final adapter = _StubAdapter(jsonEncode(_row(status: 'pending')));
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = RemindersRepository(dio);

    final reminder = await repository.reactivateReminder('reminder-1');

    expect(adapter.lastOptions!.path, '/reminders/reminder-1/reactivate');
    expect(adapter.lastOptions!.method, 'POST');
    expect(reminder.status, ReminderStatus.pending);
  });
}
