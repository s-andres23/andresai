import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_permission_state.dart';

/// A single previously-scheduled local notification, as reported by the
/// platform's pending-notification-request API.
class ScheduledNotification {
  const ScheduledNotification({required this.id, required this.payload});

  final int id;
  final String? payload;
}

/// The subset of `flutter_local_notifications`' surface that
/// [LocalNotificationService] depends on.
///
/// `FlutterLocalNotificationsPlugin` has a private constructor (it's a
/// singleton accessed via a factory), so it can't be subclassed or faked
/// directly the way this project's repositories are in tests. This
/// interface exists purely to make [LocalNotificationService]'s business
/// logic (should this reminder be scheduled? what ID? which reminders are
/// stale?) testable without touching real platform channels, and to keep
/// every `flutter_local_notifications`-specific detail -- channel setup,
/// Darwin permission flags, timezone conversion, platform branching --
/// isolated in one place ([FlutterLocalNotificationsGateway]) that could be
/// swapped out later without touching [LocalNotificationService].
abstract class NotificationPluginGateway {
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  });

  /// The payload of the notification that launched the app from fully
  /// terminated (cold start), or `null` if the app wasn't launched that
  /// way. Only meaningful immediately after [initialize]; the OS-reported
  /// launch details this reads from don't persist across further app
  /// lifecycle changes.
  Future<String?> getLaunchPayload();

  Future<NotificationPermissionStatus> getPermissionStatus();

  Future<NotificationPermissionStatus> requestPermission();

  /// Android-only capability check for whether exact-timing scheduling is
  /// currently allowed; always `true` on platforms that don't distinguish
  /// exact vs. inexact scheduling.
  Future<bool> canScheduleExactAlarms();

  /// Whether this platform exposes an "open notification settings" action
  /// the UI can offer as a shortcut.
  bool get canOpenNotificationSettings;

  Future<void> openNotificationSettings();

  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime remindAtUtc,
    required String payload,
    required bool useExactScheduling,
  });

  Future<void> cancel(int id);

  Future<List<ScheduledNotification>> pendingNotifications();
}

/// The real [NotificationPluginGateway], backed by
/// `flutter_local_notifications`.
class FlutterLocalNotificationsGateway implements NotificationPluginGateway {
  FlutterLocalNotificationsGateway()
    : _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'reminders';
  static const _channelName = 'Reminders';
  static const _channelDescription = 'AndresAI reminder notifications';

  // A fixed, app-specific identifier and GUID, as required by the Windows
  // plugin to register the app with the OS's toast notification system.
  // These just need to be stable for this app; they carry no other meaning.
  static const _windowsAppUserModelId = 'AndresAI.MobileDesktop';
  static const _windowsGuid = '2e3a9f6c-4b7d-4e8a-9c1f-6a2d8b5e7f3a';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _timeZonesInitialized = false;

  Future<void> _ensureTimeZonesInitialized() async {
    if (_timeZonesInitialized) return;
    tz_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    _timeZonesInitialized = true;
  }

  @override
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  }) async {
    await _ensureTimeZonesInitialized();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    // Never request permission as part of initialization -- this must
    // complete silently on every app launch. LocalNotificationService
    // exposes an explicit requestPermission() the UI calls contextually
    // instead (see RemindersPage).
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'AndresAI',
      appUserModelId: _windowsAppUserModelId,
      guid: _windowsGuid,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        windows: windowsSettings,
      ),
      onDidReceiveNotificationResponse: (response) =>
          onNotificationTapped(response.payload),
    );
  }

  @override
  Future<String?> getLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final enabled = await _androidPlugin()?.areNotificationsEnabled();
        return _statusFromBool(enabled);
      case TargetPlatform.iOS:
        final options = await _iosPlugin()?.checkPermissions();
        return _statusFromBool(options?.isEnabled);
      case TargetPlatform.macOS:
        final options = await _macOSPlugin()?.checkPermissions();
        return _statusFromBool(options?.isEnabled);
      default:
        // Windows toast notifications are governed entirely by OS settings
        // that this plugin doesn't expose a query API for; there's no way
        // to distinguish "not asked" from "not applicable" here, so this
        // is intentionally reported the same as notDetermined rather than
        // assumed granted.
        return NotificationPermissionStatus.notDetermined;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final granted = await _androidPlugin()
            ?.requestNotificationsPermission();
        return _statusFromBool(granted);
      case TargetPlatform.iOS:
        final granted = await _iosPlugin()?.requestPermissions(
          alert: true,
          sound: true,
        );
        return _statusFromBool(granted);
      case TargetPlatform.macOS:
        final granted = await _macOSPlugin()?.requestPermissions(
          alert: true,
          sound: true,
        );
        return _statusFromBool(granted);
      default:
        return NotificationPermissionStatus.notDetermined;
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    return await _androidPlugin()?.canScheduleExactNotifications() ?? false;
  }

  @override
  bool get canOpenNotificationSettings =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<void> openNotificationSettings() async {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await _androidPlugin()?.openAppNotificationSettings();
      case TargetPlatform.iOS:
        await _iosPlugin()?.openAppNotificationSettings();
      case TargetPlatform.macOS:
        await _macOSPlugin()?.openAppNotificationSettings();
      default:
        break;
    }
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime remindAtUtc,
    required String payload,
    required bool useExactScheduling,
  }) async {
    await _ensureTimeZonesInitialized();

    // `remindAtUtc` is an absolute instant (the backend's authoritative
    // `remindAt`); `TZDateTime.from` preserves that instant and only
    // changes how it's *represented* (in the device's local timezone), so
    // this never reinterprets it as if it were already a local wall-clock
    // time.
    final scheduledDate = tz.TZDateTime.from(remindAtUtc, tz.local);

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: payload,
      scheduledDate: scheduledDate,
      androidScheduleMode: useExactScheduling
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<List<ScheduledNotification>> pendingNotifications() async {
    final pending = await _plugin.pendingNotificationRequests();
    return [
      for (final request in pending)
        ScheduledNotification(id: request.id, payload: request.payload),
    ];
  }

  AndroidFlutterLocalNotificationsPlugin? _androidPlugin() => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? _iosPlugin() => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  MacOSFlutterLocalNotificationsPlugin? _macOSPlugin() => _plugin
      .resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
      >();

  NotificationPermissionStatus _statusFromBool(bool? granted) {
    if (granted == null) return NotificationPermissionStatus.notDetermined;
    return granted
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied;
  }
}
