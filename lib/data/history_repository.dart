import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../domain/history_entry.dart';
import '../domain/maintenance_record.dart';

class HistoryRepository {
  HistoryRepository(this._api);

  final ApiClient _api;

  /// Preventive/Reactive/Annual read `MaintenanceHistory` by namespace. Work
  /// orders track their trail as `WorkOrderLog` rows instead (no
  /// `historyType` — see `OrderType.workOrder`), so they read the work-log
  /// feed the facility-management web already uses.
  Future<List<HistoryEntry>> list(OrderType type, String id) async {
    if (type == OrderType.workOrder) {
      final response = await _api.get('/api/fm/work-order/$id/work-log');
      return unwrapList(response.data)
          .map(HistoryEntry.fromWorkOrderLogJson)
          .toList();
    }
    final response = await _api.get('/api/fm/history/${type.historyType}/$id');
    return unwrapList(response.data).map(HistoryEntry.fromJson).toList();
  }
}
