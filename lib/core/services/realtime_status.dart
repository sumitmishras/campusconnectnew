import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The callback every `subscribe()` in this app passes.
///
/// `subscribe()` takes an optional status callback and every channel here
/// used to omit it, which made a channel that never joined completely
/// silent: a table missing from `supabase_realtime`, an expired token, RLS
/// refusing the subscription and a healthy socket all looked identical from
/// inside the app. The only symptom was a screen that needed pulling to
/// refresh, which is a symptom of about ten other things.
///
/// [onRejoin] is for the other half of that problem. A phone that spends a
/// minute in someone's pocket loses the socket, and Realtime re-joins on its
/// own when the app comes back — but the events that happened in between are
/// gone, and no amount of listening will replay them. Anything that arrived
/// while the socket was down has to be *fetched*. It deliberately does not
/// fire on the first join, when the caller has just loaded anyway.
void Function(RealtimeSubscribeStatus, Object?) realtimeStatus(
  String channel, {
  VoidCallback? onRejoin,
}) {
  var hasJoined = false;

  return (status, error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        debugPrint('[realtime] $channel: subscribed');
        if (hasJoined) onRejoin?.call();
        hasJoined = true;
      case RealtimeSubscribeStatus.channelError:
        // The one worth reading. Realtime puts the reason in here — most
        // often that the table is not in the publication, or that the JWT
        // the socket joined with has expired.
        debugPrint('[realtime] $channel: CHANNEL_ERROR — ${error ?? 'no detail'}');
      case RealtimeSubscribeStatus.timedOut:
        debugPrint('[realtime] $channel: timed out joining');
      case RealtimeSubscribeStatus.closed:
        debugPrint('[realtime] $channel: closed');
    }
  };
}
