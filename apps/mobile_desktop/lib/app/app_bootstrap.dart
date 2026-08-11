import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';

/// One-time app startup work that must complete before [runApp].
class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize() async {
    AppConfig.validate();

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }
}
