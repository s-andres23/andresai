import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/notifications/local_notification_service.dart';

/// One-time app startup work that must complete before [runApp].
class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize() async {
    AppConfig.validate();

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );

    // Sets up the local notification plugin only -- this must never prompt
    // for permission itself. RemindersPage requests permission explicitly
    // and contextually instead.
    await LocalNotificationService.instance.initialize();
  }
}
