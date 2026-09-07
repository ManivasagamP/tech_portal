import 'dart:async';

/// Equivalent of the web `offline-queue-changed` window event. Fired on every
/// enqueue and at the end of every flush, so lists and the time tracker can
/// correct themselves after a mutation syncs or gets dropped as a conflict.
class QueueBus {
  final _controller = StreamController<int>.broadcast();
  var _tick = 0;

  /// Each event carries a fresh tick. A stream of a constant value would
  /// collapse into an equal AsyncValue, and Riverpod would stop notifying
  /// dependents after the very first queue change.
  Stream<int> get stream => _controller.stream;

  void notify() {
    if (!_controller.isClosed) _controller.add(++_tick);
  }

  void dispose() => _controller.close();
}
