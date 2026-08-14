import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/features/calendar/calendar_repository.dart';

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
}
