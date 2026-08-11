import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/network/api_client.dart';

/// Minimal screen used to verify that the app foundation works end to end:
/// Supabase auth (sign in / sign out) and an authenticated call to the
/// NestJS backend through the shared Dio client.
///
/// This is a bootstrap diagnostic, not the Tasks feature.
class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key});

  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSigningIn = false;
  String? _authError;

  bool _isCallingApi = false;
  String? _apiResult;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isSigningIn = true;
      _authError = null;
    });

    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .signInWithPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (e) {
      setState(() => _authError = e.toString());
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut();
  }

  Future<void> _testApiConnection() async {
    setState(() {
      _isCallingApi = true;
      _apiResult = null;
    });

    try {
      final response = await ref.read(apiClientProvider).get<String>('');
      setState(
        () => _apiResult = 'Success (${response.statusCode}): ${response.data}',
      );
    } on DioException catch (e) {
      setState(() => _apiResult = 'Failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _isCallingApi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    final isSignedIn = session != null;

    return Scaffold(
      appBar: AppBar(title: const Text('AndresAI — Bootstrap')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            Text('Auth status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              isSignedIn ? 'Signed in as ${session.user.email}' : 'Signed out',
            ),
            const SizedBox(height: 24),
            if (!isSignedIn) ...[
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isSigningIn ? null : _signIn,
                child: _isSigningIn
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign In'),
              ),
              if (_authError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _authError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ] else
              OutlinedButton(
                onPressed: _signOut,
                child: const Text('Sign Out'),
              ),
            const SizedBox(height: 32),
            Text(
              'Backend connectivity',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _isCallingApi ? null : _testApiConnection,
              child: _isCallingApi
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test API Connection'),
            ),
            if (_apiResult != null) ...[
              const SizedBox(height: 8),
              Text(_apiResult!),
            ],
          ],
        ),
      ),
    );
  }
}
