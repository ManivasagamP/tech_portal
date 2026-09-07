import '../core/network/api_client.dart';
import '../core/network/envelope.dart';
import '../domain/history_entry.dart';
import '../domain/maintenance_record.dart';

class HistoryRepository {
  HistoryRepository(this._api);

  final ApiClient _api;

  /// Work orders have no history namespace of their own. The web asks for the
  /// Preventive namespace with a work-order id, which simply returns nothing;
  /// that behaviour is kept deliberately rather than inventing a new endpoint.
  Future<List<HistoryEntry>> list(OrderType type, String id) async {
    final historyType = type.historyType ?? OrderType.preventive.historyType!;
    final response = await _api.get('/api/fm/history/$historyType/$id');
    return unwrapList(response.data).map(HistoryEntry.fromJson).toList();
  }
}
