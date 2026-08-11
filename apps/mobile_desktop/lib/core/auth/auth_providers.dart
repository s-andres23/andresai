import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase client, initialized in `AppBootstrap` before `runApp`.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Emits every Supabase auth state change (sign in, sign out, token
/// refresh), so the UI can react to session changes as they happen.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// The current Supabase session, or null when signed out.
///
/// Derived from [authStateChangesProvider] so it updates as soon as the
/// session changes, falling back to the client's current session before
/// the stream has emitted its first event.
final currentSessionProvider = Provider<Session?>((ref) {
  final authState = ref.watch(authStateChangesProvider).value;
  if (authState != null) return authState.session;
  return ref.watch(supabaseClientProvider).auth.currentSession;
});
