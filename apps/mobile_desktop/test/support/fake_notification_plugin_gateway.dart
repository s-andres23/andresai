import 'package:mobile_desktop/core/notifications/notification_permission_state.dart';
import 'package:mobile_desktop/core/notifications/notification_plugin_gateway.dart';

/// Records what a scheduled-at call was made with, for assertions.
class FakeScheduledNotification {
  FakeScheduledNotification({
    required this.title,
    required this.body,
    required this.remindAtUtc,
    required this.payload,
    required this.useExactScheduling,
  });

  final String title;
  final String body;
  final DateTime remindAtUtc;
  final String payload;
  final bool useExactScheduling;
}

/// An in-memory [NotificationPluginGateway] for tests, so
/// [LocalNotificationService]'s business logic can be exercised without
/// touching real platform channels.
///
/// Shared across the notification service's own tests and every other test
/// file (`RemindersController`, `RemindersPage`, `HomeShell`) that needs to
/// override `localNotificationServiceProvider` so those tests aren't
/// accidentally exercising real platform-channel calls.
class FakeNotificationPluginGateway implements NotificationPluginGateway {
  FakeNotificationPluginGateway({
    NotificationPermissionStatus initialStatus =
        NotificationPermissionStatus.granted,
    this.canScheduleExact = true,
  }) : _status = initialStatus;

  NotificationPermissionStatus _status;
  bool canScheduleExact;
  void Function(String? payload)? _onNotificationTapped;

  final Map<int, FakeScheduledNotification> scheduled = {};
  final List<int> cancelCalls = [];
  final List<int> showNowCalls = [];
  int scheduleCallCount = 0;
  bool initializeCalled = false;
  bool openSettingsCalled = false;

  /// Makes the next (and every subsequent) `showNow` call throw.
  bool throwOnShowNow = false;

  /// When set, a `cancel` call for this specific notification id throws --
  /// every other id's `cancel` call succeeds normally. Lets tests verify
  /// that one reminder's failure doesn't affect another's.
  int? throwOnCancelForId;

  /// Makes the next (and every subsequent) `scheduleAt` call throw.
  bool throwOnSchedule = false;

  /// Set before [initialize] is called to simulate a cold start launched by
  /// tapping a notification with this payload; `null` simulates a normal
  /// launch. Set to a non-JSON string to simulate a malformed/unrelated
  /// launch payload.
  String? launchPayload;

  /// Makes [getLaunchPayload] throw, to test that a lookup failure never
  /// blocks `LocalNotificationService.initialize()`.
  bool throwOnGetLaunchPayload = false;

  @override
  Future<void> initialize({
    required void Function(String? payload) onNotificationTapped,
  }) async {
    initializeCalled = true;
    _onNotificationTapped = onNotificationTapped;
  }

  /// Simulates the user tapping a notification with the given [payload].
  void simulateTap(String? payload) => _onNotificationTapped?.call(payload);

  @override
  Future<String?> getLaunchPayload() async {
    if (throwOnGetLaunchPayload) throw Exception('launch details failed');
    return launchPayload;
  }

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async => _status;

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    _status = NotificationPermissionStatus.granted;
    return _status;
  }

  void setStatus(NotificationPermissionStatus status) => _status = status;

  @override
  Future<bool> canScheduleExactAlarms() async => canScheduleExact;

  @override
  bool get canOpenNotificationSettings => true;

  @override
  Future<void> openNotificationSettings() async {
    openSettingsCalled = true;
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
    if (throwOnSchedule) throw Exception('schedule failed');
    scheduleCallCount++;
    scheduled[id] = FakeScheduledNotification(
      title: title,
      body: body,
      remindAtUtc: remindAtUtc,
      payload: payload,
      useExactScheduling: useExactScheduling,
    );
  }

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (throwOnShowNow) throw Exception('showNow failed');
    showNowCalls.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    if (id == throwOnCancelForId) throw Exception('cancel failed');
    cancelCalls.add(id);
    scheduled.remove(id);
  }

  @override
  Future<List<ScheduledNotification>> pendingNotifications() async {
    return [
      for (final entry in scheduled.entries)
        ScheduledNotification(id: entry.key, payload: entry.value.payload),
    ];
  }
}
