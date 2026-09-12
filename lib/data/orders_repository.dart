// ignore_for_file: prefer_initializing_formals — named params cannot be private
import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';
import '../domain/maintenance_record.dart';

class OrdersPage {
  const OrdersPage({required this.records, required this.fromCache});

  final List<MaintenanceRecord> records;
  final bool fromCache;
}

class OrderDetailPage {
  const OrderDetailPage({required this.record, required this.fromCache});

  final MaintenanceRecord record;
  final bool fromCache;
}

class OrdersRepository {
  OrdersRepository({required SyncClient sync, required ApiClient api})
      : _sync = sync,
        _api = api;

  final SyncClient _sync;
  final ApiClient _api;

  /// One kind, served from cache when there is no signal — the job list is the
  /// entry point to everything else.
  Future<OrdersPage> listByType(OrderType type, String technicianId) async {
    final read = await _sync.syncGet('${type.listPath}/$technicianId');
    return OrdersPage(
      records: MaintenanceRecord.listFrom(unwrapList(read.data)),
      fromCache: read.fromCache,
    );
  }

  /// A technician's assigned work orders. Generation (2026-09-12) now
  /// produces a single unified Work Order for every kind — PM/reactive/
  /// annual are templates and schedules, not tasks in their own right, and
  /// the technician endpoint already scopes to `assignedTechnician` — so
  /// there is no separate per-type fetch to fan out to any more.
  Future<OrdersPage> listAll(String technicianId) =>
      listByType(OrderType.workOrder, technicianId);

  /// Every kind the technician could be invited to — preventive included.
  /// Preventive is hidden from the orders list and the calendar, but an invite
  /// to one is the only way its detail page is ever reached, so leaving it out
  /// would make those invites unanswerable.
  Future<List<MaintenanceRecord>> listInvites(String technicianId) async {
    final responses = await Future.wait(
      OrderType.values.map((type) async {
        try {
          final response = await _api.get('${type.listPath}/$technicianId');
          return MaintenanceRecord.listFrom(unwrapList(response.data), type);
        } catch (_) {
          return <MaintenanceRecord>[];
        }
      }),
    );

    return responses
        .expand((records) => records)
        .where((record) => record.isAssignmentPending)
        .toList();
  }

  Future<OrderDetailPage> detailPage(OrderType type, String id) async {
    final read = await _sync.syncGet('/api/fm/${type.entityPath}/$id');
    return OrderDetailPage(
      record: MaintenanceRecord.fromJson(unwrapMap(read.data)),
      fromCache: read.fromCache,
    );
  }
}
