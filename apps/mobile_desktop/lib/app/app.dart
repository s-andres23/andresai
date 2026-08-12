import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_providers.dart';
import '../features/bootstrap/bootstrap_screen.dart';
import '../features/tasks/tasks_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);

    return MaterialApp(
      title: 'AndresAI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // Signed out: the temporary bootstrap sign-in screen. Signed in: the
      // real Tasks feature.
      home: session == null ? const BootstrapScreen() : const TasksPage(),
    );
  }
}
