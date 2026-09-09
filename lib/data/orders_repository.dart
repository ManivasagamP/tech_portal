// ignore_for_file: prefer_initializing_formals — named params cannot be private
import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';
import '../domain/maintenance_record.dart';

class OrdersPage {
  const OrdersPage({
    required this.records,
    required this.fromCache,
    this.failedTypes = const [],
  });

  final List<MaintenanceRecord> records;
  final bool fromCache;

  /// Kinds whose fetch failed during [OrdersRepository.listAll] and
  /// contributed nothing — empty when every kind loaded (including the
  /// common case of a kind genuinely having zero records, which is not a
  /// failure). Diagnostic only: lets the UI tell "no records" apart from
  /// "some records couldn't be fetched" without blocking on the failure.
  final List<OrderType> failedTypes;
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

  /// All three kinds in parallel. A kind that fails contributes nothing rather
  /// than failing the whole list, so one bad endpoint cannot blank the screen
  /// — but the failure itself is still reported via [OrdersPage.failedTypes]
  /// rather than silently disappearing, so a technician who legitimately has
  /// zero assigned work can be told apart from a session that quietly failed
  /// to load some or all of it.
  Future<OrdersPage> listAll(String technicianId) async {
    final results = await Future.wait(
      kBrowsableOrderTypes.map((type) async {
        try {
          final response = await _api.get('${type.listPath}/$technicianId');
          return (type: type, records: unwrapList(response.data), ok: true);
        } catch (_) {
          return (type: type, records: <Map<String, dynamic>>[], ok: false);
        }
      }),
    );

    return OrdersPage(
      records: MaintenanceRecord.listFrom(
        results.expand((r) => r.records).toList(),
      ),
      fromCache: false,
      failedTypes: [
        for (final r in results)
          if (!r.ok) r.type,
      ],
    );
  }

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
