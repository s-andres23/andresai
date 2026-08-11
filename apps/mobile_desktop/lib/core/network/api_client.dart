import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../config/app_config.dart';
import 'auth_interceptor.dart';

/// The Dio client used for all communication with the NestJS backend.
///
/// Flutter never talks to Supabase's `tasks` table (or any business data)
/// directly — all such operations go through this client to the backend API.
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
  dio.interceptors.add(AuthInterceptor(ref.read(supabaseClientProvider)));
  return dio;
});
