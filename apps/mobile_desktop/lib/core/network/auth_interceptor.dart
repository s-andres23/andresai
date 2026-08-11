import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Attaches the current Supabase session's access token to outgoing
/// requests, so the NestJS backend can authenticate the caller.
///
/// The token is read from the Supabase client on every request rather than
/// cached, so a refreshed session is picked up automatically without any
/// extra bookkeeping.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._supabaseClient);

  final SupabaseClient _supabaseClient;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final accessToken = _supabaseClient.auth.currentSession?.accessToken;
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }
}
