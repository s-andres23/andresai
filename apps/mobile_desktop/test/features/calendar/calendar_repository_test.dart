import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';
import 'package:mobile_desktop/features/calendar/create_calendar_event_input.dart';
import 'package:mobile_desktop/features/calendar/update_calendar_event_input.dart';

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
/// what the backend's `DELETE /calendar-events/:id` endpoint responds with.
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

void main() {
  test(
    'fetchEvents calls GET /calendar-events and parses the response',
    () async {
      final adapter = _StubAdapter(
        jsonEncode([
          {
            'id': 'event-1',
            'userId': 'user-1',
            'title': 'Team sync',
            'description': null,
            'startAt': '2026-08-20T09:00:00.000Z',
            'endAt': '2026-08-20T09:30:00.000Z',
            'allDay': false,
            'location': null,
            'createdAt': '2026-08-13T00:00:00.000Z',
            'updatedAt': '2026-08-13T00:00:00.000Z',
          },
        ]),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = CalendarRepository(dio);

      final events = await repository.fetchEvents();

      expect(adapter.lastOptions!.path, '/calendar-events');
      expect(adapter.lastOptions!.method, 'GET');
      expect(events, hasLength(1));
      expect(events.single.title, 'Team sync');
      expect(events.single.allDay, false);
    },
  );

  test('fetchEvents returns an empty list for an empty response', () async {
    final dio = Dio()..httpClientAdapter = _StubAdapter(jsonEncode([]));
    final repository = CalendarRepository(dio);

    final events = await repository.fetchEvents();

    expect(events, isEmpty);
  });

  test('fetchEvents omits from/to query parameters when absent', () async {
    final adapter = _StubAdapter(jsonEncode([]));
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = CalendarRepository(dio);

    await repository.fetchEvents();

    expect(adapter.lastOptions!.queryParameters, isEmpty);
  });

  test('fetchEvents sends from/to as UTC ISO-8601 query parameters', () async {
    final adapter = _StubAdapter(jsonEncode([]));
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = CalendarRepository(dio);

    await repository.fetchEvents(
      from: DateTime.utc(2026, 8, 20),
      to: DateTime.utc(2026, 8, 21),
    );

    expect(
      adapter.lastOptions!.queryParameters['from'],
      '2026-08-20T00:00:00.000Z',
    );
    expect(
      adapter.lastOptions!.queryParameters['to'],
      '2026-08-21T00:00:00.000Z',
    );
  });

  test('createEvent posts the payload and parses the created event', () async {
    final adapter = _StubAdapter(
      jsonEncode({
        'id': 'event-2',
        'userId': 'user-1',
        'title': 'Team sync',
        'description': 'Weekly sync with the team',
        'startAt': '2026-08-20T09:00:00.000Z',
        'endAt': '2026-08-20T09:30:00.000Z',
        'allDay': false,
        'location': 'Conference room A',
        'createdAt': '2026-08-13T00:00:00.000Z',
        'updatedAt': '2026-08-13T00:00:00.000Z',
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = CalendarRepository(dio);

    final event = await repository.createEvent(
      CreateCalendarEventInput(
        title: 'Team sync',
        description: 'Weekly sync with the team',
        startAt: DateTime.utc(2026, 8, 20, 9),
        endAt: DateTime.utc(2026, 8, 20, 9, 30),
        location: 'Conference room A',
      ),
    );

    expect(adapter.lastOptions!.path, '/calendar-events');
    expect(adapter.lastOptions!.method, 'POST');
    expect(adapter.lastOptions!.data, {
      'title': 'Team sync',
      'description': 'Weekly sync with the team',
      'startAt': '2026-08-20T09:00:00.000Z',
      'endAt': '2026-08-20T09:30:00.000Z',
      'allDay': false,
      'location': 'Conference room A',
    });
    expect(event.id, 'event-2');
    expect(event.title, 'Team sync');
  });

  test('createEvent omits description and location from the payload when '
      'absent', () async {
    final adapter = _StubAdapter(
      jsonEncode({
        'id': 'event-3',
        'userId': 'user-1',
        'title': 'Focus block',
        'description': null,
        'startAt': '2026-08-20T09:00:00.000Z',
        'endAt': '2026-08-20T10:00:00.000Z',
        'allDay': false,
        'location': null,
        'createdAt': '2026-08-13T00:00:00.000Z',
        'updatedAt': '2026-08-13T00:00:00.000Z',
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = CalendarRepository(dio);

    await repository.createEvent(
      CreateCalendarEventInput(
        title: 'Focus block',
        startAt: DateTime.utc(2026, 8, 20, 9),
        endAt: DateTime.utc(2026, 8, 20, 10),
      ),
    );

    expect(adapter.lastOptions!.data, {
      'title': 'Focus block',
      'startAt': '2026-08-20T09:00:00.000Z',
      'endAt': '2026-08-20T10:00:00.000Z',
      'allDay': false,
    });
  });

  test('updateEvent patches /calendar-events/:id with the full payload and '
      'parses the response', () async {
    final adapter = _StubAdapter(
      jsonEncode({
        'id': 'event-1',
        'userId': 'user-1',
        'title': 'Team sync (updated)',
        'description': 'Now with an agenda',
        'startAt': '2026-08-20T10:00:00.000Z',
        'endAt': '2026-08-20T10:30:00.000Z',
        'allDay': false,
        'location': 'Conference room B',
        'createdAt': '2026-08-13T00:00:00.000Z',
        'updatedAt': '2026-08-14T00:00:00.000Z',
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = CalendarRepository(dio);

    final event = await repository.updateEvent(
      'event-1',
      UpdateCalendarEventInput(
        title: 'Team sync (updated)',
        description: 'Now with an agenda',
        startAt: DateTime.utc(2026, 8, 20, 10),
        endAt: DateTime.utc(2026, 8, 20, 10, 30),
        allDay: false,
        location: 'Conference room B',
      ),
    );

    expect(adapter.lastOptions!.path, '/calendar-events/event-1');
    expect(adapter.lastOptions!.method, 'PATCH');
    expect(adapter.lastOptions!.data, {
      'title': 'Team sync (updated)',
      'description': 'Now with an agenda',
      'startAt': '2026-08-20T10:00:00.000Z',
      'endAt': '2026-08-20T10:30:00.000Z',
      'allDay': false,
      'location': 'Conference room B',
    });
    expect(event.title, 'Team sync (updated)');
    expect(event.location, 'Conference room B');
  });

  test(
    'updateEvent sends explicit nulls to clear description and location',
    () async {
      final adapter = _StubAdapter(
        jsonEncode({
          'id': 'event-1',
          'userId': 'user-1',
          'title': 'Team sync',
          'description': null,
          'startAt': '2026-08-20T09:00:00.000Z',
          'endAt': '2026-08-20T09:30:00.000Z',
          'allDay': false,
          'location': null,
          'createdAt': '2026-08-13T00:00:00.000Z',
          'updatedAt': '2026-08-14T00:00:00.000Z',
        }),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = CalendarRepository(dio);

      await repository.updateEvent(
        'event-1',
        UpdateCalendarEventInput(
          title: 'Team sync',
          startAt: DateTime.utc(2026, 8, 20, 9),
          endAt: DateTime.utc(2026, 8, 20, 9, 30),
          allDay: false,
        ),
      );

      expect(adapter.lastOptions!.data, {
        'title': 'Team sync',
        'description': null,
        'startAt': '2026-08-20T09:00:00.000Z',
        'endAt': '2026-08-20T09:30:00.000Z',
        'allDay': false,
        'location': null,
      });
    },
  );

  test('deleteEvent sends DELETE /calendar-events/:id', () async {
    final adapter = _NoContentAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final repository = CalendarRepository(dio);

    await repository.deleteEvent('event-1');

    expect(adapter.lastOptions!.path, '/calendar-events/event-1');
    expect(adapter.lastOptions!.method, 'DELETE');
  });
}
