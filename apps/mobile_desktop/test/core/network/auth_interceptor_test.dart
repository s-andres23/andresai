import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/network/auth_interceptor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records the [RequestOptions] Dio would have sent, without performing any
/// real network I/O.
class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('does not attach an Authorization header when signed out', () async {
    final supabaseClient = SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
    );
    final adapter = _RecordingAdapter();
    final dio = Dio()
      ..httpClientAdapter = adapter
      ..interceptors.add(AuthInterceptor(supabaseClient));

    await dio.get('/ping');

    expect(adapter.lastOptions!.headers.containsKey('Authorization'), isFalse);
  });
}
