import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Unlike iOS's `FlutterAppDelegate` (which conforms to
  // `UNUserNotificationCenterDelegate` transitively through
  // `FlutterAppLifeCycleProvider`), macOS's `FlutterAppDelegate` only
  // conforms to `FlutterAppLifecycleProvider`, which is unrelated to
  // `UNUserNotificationCenterDelegate`. flutter_local_notifications' macOS
  // plugin already sets itself as `UNUserNotificationCenter.current().delegate`
  // during its own plugin registration (see
  // `FlutterLocalNotificationsPlugin.register(with:)`, invoked via
  // `RegisterGeneratedPlugins` in `MainFlutterWindow`), which runs before
  // this class's lifecycle callbacks. An earlier version of this file
  // additionally set `UNUserNotificationCenter.current().delegate = self as?
  // UNUserNotificationCenterDelegate` here -- since that cast always fails
  // on macOS, it silently overwrote the plugin's delegate with `nil`,
  // breaking foreground notification presentation and tap handling. Do not
  // reintroduce that line; no delegate assignment is needed here.

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
