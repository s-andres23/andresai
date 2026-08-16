import 'package:flutter/material.dart';

import '../features/calendar/calendar_page.dart';
import '../features/reminders/reminders_page.dart';
import '../features/tasks/tasks_page.dart';

/// Temporary navigation shell for switching between the Tasks, Calendar, and
/// Reminders features while signed in.
///
/// This is not the final AndresAI navigation, just a minimal way to reach
/// these features during V0.1 development.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  // An IndexedStack (rather than only building the selected page) keeps
  // every page's controller alive across tab switches, so switching tabs
  // doesn't re-trigger a network fetch every time.
  static const _pages = [TasksPage(), CalendarPage(), RemindersPage()];

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
