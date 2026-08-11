/// Application configuration sourced from compile-time environment values.
///
/// Values are provided via `--dart-define` so no secrets are hardcoded or
/// committed to the repository. The Supabase anon/publishable key is safe to
/// ship in the client; the Supabase service role key must never appear here.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Throws a descriptive error if required configuration is missing, so
  /// misconfiguration fails fast at startup instead of causing obscure
  /// network or auth errors later.
  static void validate() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      if (apiBaseUrl.isEmpty) 'API_BASE_URL',
    ];

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define values: ${missing.join(', ')}',
      );
    }
  }
}
