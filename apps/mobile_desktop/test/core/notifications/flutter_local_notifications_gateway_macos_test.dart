import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/notifications/notification_permission_state.dart';
import 'package:mobile_desktop/core/notifications/notification_plugin_gateway.dart';

/// Covers the macOS-specific parts of [FlutterLocalNotificationsGateway]:
/// the custom `andresai/notification_authorization` channel used to read
/// the true `UNAuthorizationStatus` (since flutter_local_notifications'
/// own `checkPermissions()` can't distinguish "never asked" from "denied"
/// on macOS -- both collapse to the same boolean), and that
/// `requestPermission()` genuinely delegates to the plugin's native
/// `requestPermissions` call rather than being a no-op.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const authChannel = MethodChannel('andresai/notification_authorization');
  const pluginChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(authChannel, null);
    messenger.setMockMethodCallHandler(pluginChannel, null);
  });

  void mockAuthorizationStatus(int? rawStatus) {
    messenger.setMockMethodCallHandler(authChannel, (call) async {
      expect(call.method, 'getAuthorizationStatus');
      return rawStatus;
    });
  }

  group('getPermissionStatus on macOS', () {
    test('reports notDetermined before authorization has ever been requested '
        '(UNAuthorizationStatus.notDetermined, rawValue 0)', () async {
      mockAuthorizationStatus(0);
      final gateway = FlutterLocalNotificationsGateway();

      final status = await gateway.getPermissionStatus();

      expect(status, NotificationPermissionStatus.notDetermined);
    });

    test(
      'reports denied for UNAuthorizationStatus.denied (rawValue 1)',
      () async {
        mockAuthorizationStatus(1);
        final gateway = FlutterLocalNotificationsGateway();

        final status = await gateway.getPermissionStatus();

        expect(status, NotificationPermissionStatus.denied);
      },
    );

    test(
      'reports granted for UNAuthorizationStatus.authorized (rawValue 2)',
      () async {
        mockAuthorizationStatus(2);
        final gateway = FlutterLocalNotificationsGateway();

        final status = await gateway.getPermissionStatus();

        expect(status, NotificationPermissionStatus.granted);
      },
    );

    test('reports granted for provisional/ephemeral authorization (rawValues '
        '3 and 4)', () async {
      final gateway = FlutterLocalNotificationsGateway();

      mockAuthorizationStatus(3);
      expect(
        await gateway.getPermissionStatus(),
        NotificationPermissionStatus.granted,
      );

      mockAuthorizationStatus(4);
      expect(
        await gateway.getPermissionStatus(),
        NotificationPermissionStatus.granted,
      );
    });

    test('falls back to the plugin\'s own (less precise) checkPermissions() '
        'if the custom authorization channel is unavailable, rather than '
        'crashing', () async {
      // Simulates a normal running app (the plugin itself is registered
      // as usual) where only the custom auth-status channel has no
      // handler -> MissingPluginException on that specific channel.
      FlutterLocalNotificationsPlatform.instance =
          MacOSFlutterLocalNotificationsPlugin();
      messenger.setMockMethodCallHandler(
        pluginChannel,
        (call) async => call.method == 'checkPermissions'
            ? <String, bool>{'isEnabled': true}
            : null,
      );
      final gateway = FlutterLocalNotificationsGateway();

      final status = await gateway.getPermissionStatus();

      // The fallback path is inherently unable to distinguish
      // notDetermined from denied -- that's the whole reason the custom
      // channel exists -- so this only asserts it degrades gracefully
      // (using whatever checkPermissions() reports) instead of throwing.
      expect(status, NotificationPermissionStatus.granted);
    });
  });

  group('requestPermission on macOS', () {
    test('delegates to MacOSFlutterLocalNotificationsPlugin.requestPermissions '
        'with alert and sound requested', () async {
      FlutterLocalNotificationsPlatform.instance =
          MacOSFlutterLocalNotificationsPlugin();
      MethodCall? capturedCall;
      messenger.setMockMethodCallHandler(pluginChannel, (call) async {
        capturedCall = call;
        if (call.method == 'requestPermissions') return true;
        return null;
      });
      final gateway = FlutterLocalNotificationsGateway();

      final status = await gateway.requestPermission();

      expect(capturedCall, isNotNull);
      expect(capturedCall!.method, 'requestPermissions');
      final arguments = capturedCall!.arguments as Map<dynamic, dynamic>;
      expect(arguments['alert'], isTrue);
      expect(arguments['sound'], isTrue);
      expect(status, NotificationPermissionStatus.granted);
    });

    test('a declined native prompt maps to denied', () async {
      FlutterLocalNotificationsPlatform.instance =
          MacOSFlutterLocalNotificationsPlugin();
      messenger.setMockMethodCallHandler(
        pluginChannel,
        (call) async => call.method == 'requestPermissions' ? false : null,
      );
      final gateway = FlutterLocalNotificationsGateway();

      final status = await gateway.requestPermission();

      expect(status, NotificationPermissionStatus.denied);
    });
  });
}
