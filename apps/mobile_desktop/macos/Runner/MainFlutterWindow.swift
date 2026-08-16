import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerNotificationAuthorizationChannel(with: flutterViewController)

    super.awakeFromNib()
  }

  /// A small custom channel exposing the raw `UNAuthorizationStatus`.
  ///
  /// flutter_local_notifications' `checkPermissions()` only reports a
  /// boolean derived from `authorizationStatus == .authorized` (see its
  /// macOS plugin source), which can't distinguish "never asked"
  /// (`.notDetermined`) from "explicitly denied" (`.denied`) -- both
  /// collapse to `false`. AndresAI needs that distinction to decide whether
  /// to show its own permission explanation before requesting (see
  /// `FlutterLocalNotificationsGateway.getPermissionStatus` on the Dart
  /// side), so this reads the status directly from `UNUserNotificationCenter`
  /// instead of guessing from the plugin's collapsed boolean.
  private func registerNotificationAuthorizationChannel(
    with controller: FlutterViewController
  ) {
    let channel = FlutterMethodChannel(
      name: "andresai/notification_authorization",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getAuthorizationStatus" else {
        result(FlutterMethodNotImplemented)
        return
      }
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        result(settings.authorizationStatus.rawValue)
      }
    }
  }
}
