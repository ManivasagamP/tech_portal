import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/offline/sync_client.dart';
import '../data/assignment_repository.dart';
import '../data/history_repository.dart';
import '../domain/history_entry.dart';
import '../domain/maintenance_record.dart';
import 'orders_controller.dart';
import 'providers.dart';

typedef OrderKey = ({OrderType type, String id});

class OrderDetail {
  const OrderDetail({
    required this.record,
    required this.fromCache,
    required this.queuedComplete,
  });

  final MaintenanceRecord record;
  final bool fromCache;

  /// A close queued offline has not reached the server, so `completedDate` is
  /// still null. Without this the screen would fall back to "in progress" for
  /// a record the technician has already closed.
  final bool queuedComplete;
}

class OrderDetailController extends FamilyAsyncNotifier<OrderDetail, OrderKey> {
  var _disposed = false;

  @override
  Future<OrderDetail> build(OrderKey arg) {
    ref.onDispose(() => _disposed = true);
    // A queued mutation syncing or being dropped as a conflict moves the
    // record without this screen knowing.
    ref.listen(queueChangedProvider, (_, _) => refresh());
    return _load();
  }

  Future<OrderDetail> _load() async {
    final repository = ref.read(ordersRepositoryProvider);
    final page = await repository.detailPage(arg.type, arg.id);
    return OrderDetail(
      record: page.record,
      fromCache: page.fromCache,
      queuedComplete: await _hasQueuedComplete(),
    );
  }

  Future<bool> _hasQueuedComplete() async {
    final endpoint = '/api/fm/${arg.type.completePath}/${arg.id}/time-tracking';
    final mutations = await ref.read(offlineDbProvider).listMutations();
    return mutations.any((m) {
      final body = m.body;
      return m.url == endpoint && body is Map && body['action'] == 'complete';
    });
  }

  /// Silent refetch — the screen keeps its current content while it runs, as
  /// the web's `fetchData(true)` does.
  Future<void> refresh() async {
    final result = await AsyncValue.guard(_load);
    if (_disposed) return;
    state = result;
  }

  Future<String?> respondToInvite({
    required bool accept,
    String? reason,
  }) async {
    try {
      final write = await ref
          .read(assignmentRepositoryProvider)
          .respond(arg.type, arg.id, accept: accept, reason: reason);
      await refresh();
      // The orders list carries the same record and would keep showing the
      // invite until it refetched on its own.
      ref.invalidate(ordersControllerProvider);
      return write.synced ? null : kOfflineQueuedMessage;
    } catch (e) {
      return 'Failed to respond to this job assignment offer.';
    }
  }
}

final orderDetailControllerProvider =
    AsyncNotifierProvider.family<OrderDetailController, OrderDetail, OrderKey>(
      OrderDetailController.new,
    );

final assignmentRepositoryProvider = Provider<AssignmentRepository>(
  (ref) => AssignmentRepository(ref.watch(syncClientProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(apiClientProvider)),
);

final orderHistoryProvider =
    FutureProvider.family<List<HistoryEntry>, OrderKey>(
      (ref, key) => ref.watch(historyRepositoryProvider).list(key.type, key.id),
    );
