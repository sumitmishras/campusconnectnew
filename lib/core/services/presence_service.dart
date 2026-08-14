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

  Timer? _heartbeat;
  Future<void> Function()? _onHeartbeat;

  /// How often `user_presence.last_active` is refreshed while the app is in
  /// the foreground.
  ///
  /// `expire_stale_presence()` (0010) flips anyone whose `last_active` is more
  /// than two minutes old to offline, so without a beat inside that window a
  /// student reading a long thread is marked offline while they are looking at
  /// it — and the last-seen everyone else reads is the moment they opened the
  /// app, not the moment they left it.
  static const Duration heartbeatInterval = Duration(seconds: 45);

  /// Ids currently connected, as last reported by the channel.
  Set<String> get onlineIds => Set.unmodifiable(_ids);

  Stream<Set<String>> get changes => _online.stream;

  bool isOnline(String userId) => _ids.contains(userId);

  /// Joins the campus channel and announces this student. Safe to call more
  /// than once and safe to call in mock mode, where it does nothing.
  ///
  /// [onHeartbeat] refreshes the durable `user_presence` row — the channel is
  /// what the live dot follows, but the timestamp other clients read when they
  /// load a profile comes from the table, and a table only knows what it was
  /// last told.
  Future<void> start(String userId, {Future<void> Function()? onHeartbeat}) async {
    if (!SupabaseService.isReady || userId.isEmpty) return;
    if (_channel != null && _selfId == userId) {
      // Already tracking this student; a repeat call is a foreground event, so
      // take the opportunity to stamp the row.
      if (onHeartbeat != null) _onHeartbeat = onHeartbeat;
      unawaited(_beat());
      return;
    }
    await stop();

    _selfId = userId;
    _onHeartbeat = onHeartbeat;
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

    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => unawaited(_beat()));
    unawaited(_beat());
  }

  Future<void> _beat() async {
    final beat = _onHeartbeat;
    if (beat == null || _selfId == null) return;
    try {
      await beat();
    } catch (_) {
      // A missed beat costs at most one interval of last-seen accuracy, and
      // the next one repairs it. Never worth interrupting the student for.
    }
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
    _heartbeat?.cancel();
    _heartbeat = null;
    _onHeartbeat = null;

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
