import 'dart:async';

/// Collapses a burst of calls into the last one.
///
/// Used for the Discover search box: without it every keystroke is a query,
/// and on a real backend a five-letter name is five round trips of which four
/// are already stale by the time they land.
///
/// [dispose] must be called by the owner — a pending timer holds its callback,
/// and that callback holds the provider.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    if (delay <= Duration.zero) {
      action();
      return;
    }
    _timer = Timer(delay, action);
  }

  /// Drops a pending call without running it. Used when something else
  /// supersedes the debounced work — a pull-to-refresh, or the field being
  /// cleared, both of which reload immediately.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
