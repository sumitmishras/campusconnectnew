import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'realtime_status.dart';
import 'supabase_service.dart';

/// Live "who is online right now", over a Realtime presence channel.
///
/// `user_presence` is the durable fallback and is still written on every
/// foreground/background transition (see `ProfileRepository.setPresence`), but
/// it is a table — a student who closes the app is only marked offline when
/// `expire_stale_presence()` next runs, up to a minute later. The socket knows
/// immediately, because leaving the channel *is* the event.
///
/// Deliberately not published to Postgres changes: presence flips every few
/// seconds per active student and replicating it would generate more traffic
/// than the messages do.
class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final _online = StreamController<Set<String>>.broadcast();
  final Set<String> _ids = {};

  RealtimeChannel? _channel;
  String? _selfId;

  /// Ids currently connected, as last reported by the channel.
  Set<String> get onlineIds => Set.unmodifiable(_ids);

  Stream<Set<String>> get changes => _online.stream;

  bool isOnline(String userId) => _ids.contains(userId);

  /// Joins the campus channel and announces this student. Safe to call more
  /// than once and safe to call in mock mode, where it does nothing.
  Future<void> start(String userId) async {
    if (!SupabaseService.isReady || userId.isEmpty) return;
    if (_channel != null && _selfId == userId) return;
    await stop();

    _selfId = userId;
    final log = realtimeStatus('cc-presence');
    final channel = SupabaseService.client.channel(
      'cc-presence',
      // The presence key identifies this client's entry. Keying on the student
      // means two devices signed into the same account collapse into one
      // presence rather than counting twice.
      opts: RealtimeChannelConfig(key: userId),
    );

    channel
      ..onPresenceSync((_) => _sync(channel))
      ..onPresenceJoin((_) => _sync(channel))
      ..onPresenceLeave((_) => _sync(channel))
      ..subscribe((status, error) async {
        log(status, error);
        if (status != RealtimeSubscribeStatus.subscribed) return;
        // Re-announced on every join, not just the first: after a dropped
        // socket this client's entry is gone from everyone else's roster and
        // only tracking again puts it back.
        await channel.track({'user_id': userId});
      });

    _channel = channel;
  }

  void _sync(RealtimeChannel channel) {
    final next = <String>{};
    for (final entries in channel.presenceState()) {
      for (final presence in entries.presences) {
        final id = presence.payload['user_id'];
        if (id is String && id.isNotEmpty) next.add(id);
      }
    }

    if (next.length == _ids.length && next.containsAll(_ids)) return;
    _ids
      ..clear()
      ..addAll(next);
    if (!_online.isClosed) _online.add(onlineIds);
  }

  /// Leaves the channel — called on sign-out, so the student stops showing as
  /// online the moment they log out rather than when the row decays.
  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _selfId = null;
    _ids.clear();
    if (channel == null) return;
    try {
      await channel.untrack();
      await SupabaseService.client.removeChannel(channel);
    } catch (_) {
      // A socket that is already gone needs no tearing down.
    }
  }
}
