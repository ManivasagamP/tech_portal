import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/offline/queue_bus.dart';

void main() {
  test('every notify carries a distinct value', () async {
    final bus = QueueBus();
    addTearDown(bus.dispose);

    final seen = <int>[];
    final sub = bus.stream.listen(seen.add);

    bus.notify();
    bus.notify();
    bus.notify();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // Equal consecutive values would collapse into an identical AsyncValue and
    // stop Riverpod notifying dependents after the first queue change.
    expect(seen, [1, 2, 3]);
  });
}
