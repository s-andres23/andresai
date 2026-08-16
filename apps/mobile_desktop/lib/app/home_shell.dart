import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/local_notification_service.dart';
import '../core/notifications/notification_payload.dart';
import '../features/calendar/calendar_page.dart';
import '../features/reminders/reminders_page.dart';
import '../features/tasks/tasks_page.dart';

/// Temporary navigation shell for switching between the Tasks, Calendar, and
/// Reminders features while signed in.
///
/// This is not the final AndresAI navigation, just a minimal way to reach
/// these features during V0.1 development.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;
  StreamSubscription<NotificationPayload>? _notificationTapSubscription;

  // An IndexedStack (rather than only building the selected page) keeps
  // every page's controller alive across tab switches, so switching tabs
  // doesn't re-trigger a network fetch every time.
  static const _pages = [TasksPage(), CalendarPage(), RemindersPage()];
  static const _remindersTabIndex = 2;

  @override
  void initState() {
    super.initState();

    // If this app process was cold-started by tapping a reminder
    // notification, the payload was captured during
    // LocalNotificationService.initialize() (which ran before runApp, long
    // before this widget existed) and is waiting to be consumed exactly
    // once. Set the initial tab directly rather than via setState -- this
    // runs before the first build, so there's nothing to schedule a
    // rebuild for.
    final initialLaunchPayload = ref
        .read(localNotificationServiceProvider)
        .consumeInitialLaunchPayload();
    if (initialLaunchPayload != null) {
      _selectedIndex = _remindersTabIndex;
    }

    // Tapping a reminder notification while the app is already running
    // (foreground/background) should bring the user to the Reminders tab.
    // The app has no deep-link routing yet, so this is intentionally just a
    // tab switch rather than opening the specific reminder.
    _notificationTapSubscription = ref
        .read(localNotificationServiceProvider)
        .onNotificationTapped
        .listen((_) {
          if (mounted) setState(() => _selectedIndex = _remindersTabIndex);
        });
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Reminders',
          ),
        ],
      ),
    );
  }
}
