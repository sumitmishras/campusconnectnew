import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Owns the single Supabase client and its initialisation.
///
/// [initialize] is a no-op when no credentials were supplied, so `main()` can
/// call it unconditionally and the app still boots in mock mode.
class SupabaseService {
  const SupabaseService._();

  static bool _ready = false;

  /// True once a real client exists. Everything that touches the network
  /// checks this rather than `AppConfig.useSupabase`, so a failed init cannot
  /// leave the app trying to use a client that was never created.
  static bool get isReady => _ready;

  static SupabaseClient get client {
    if (!_ready) {
      throw StateError(
        'Supabase is not configured. Pass --dart-define=SUPABASE_URL and '
        '--dart-define=SUPABASE_ANON_KEY, or let the app run in mock mode.',
      );
    }
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    if (_ready || !AppConfig.useSupabase) return;

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // Keeps the session across restarts in secure storage.
        autoRefreshToken: true,
      ),
      // Chat leans on Realtime; a slightly higher event rate stops a busy
      // club thread from being throttled at the socket.
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 20,
      ),
    );
    _ready = true;
  }
}
