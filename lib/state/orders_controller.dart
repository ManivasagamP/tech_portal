import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/envelope.dart';
import '../data/orders_repository.dart';
import '../domain/maintenance_record.dart';
import 'auth_controller.dart';
import 'providers.dart';

class OrdersState {
  const OrdersState({
    this.searchQuery = '',
    this.records = const [],
    this.loading = false,
    this.fromCache = false,
    this.error,
  });

  final String searchQuery;
  final List<MaintenanceRecord> records;
  final bool loading;
  final bool fromCache;
  final String? error;

  OrdersState copyWith({
    String? searchQuery,
    List<MaintenanceRecord>? records,
    bool? loading,
    bool? fromCache,
    String? error,
    bool clearError = false,
  }) =>
      OrdersState(
        searchQuery: searchQuery ?? this.searchQuery,
        records: records ?? this.records,
        loading: loading ?? this.loading,
        fromCache: fromCache ?? this.fromCache,
        error: clearError ? null : (error ?? this.error),
      );

  /// Search, then newest-first — the only two things left to do to the list
  /// now that the priority/status/date filter sheet is gone (the technician
  /// endpoint already scopes to their own work orders).
  List<MaintenanceRecord> get visibleRecords {
    var result = records;

    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((r) {
        // Search leads with the record's own title, unlike the card, which
        // leads with the asset.
        final title =
            (firstNonEmpty([r.titleField, r.subRequest, r.assetName]) ?? '')
                .toLowerCase();
        final description =
            (firstNonEmpty([r.description, r.taskDescription]) ?? '')
                .toLowerCase();
        final refId = (r.referenceId ?? '').toLowerCase();
        final location = (r.location ?? '').toLowerCase();
        return title.contains(query) ||
            description.contains(query) ||
            refId.contains(query) ||
            location.contains(query);
      }).toList();
    }

    final sorted = [...result];
    sorted.sort((a, b) {
      final dateA = a.effectiveDate?.millisecondsSinceEpoch ?? 0;
      final dateB = b.effectiveDate?.millisecondsSinceEpoch ?? 0;
      return dateB.compareTo(dateA);
    });
    return sorted;
  }
}

class OrdersController extends Notifier<OrdersState> {
  /// A pull-to-refresh does not cancel a fetch already in flight from the
  /// initial load. Without this a stale response landing last could
  /// overwrite the fresher one.
  int _requestId = 0;

  @override
  OrdersState build() {
    // A queued mutation flushing — synced or dropped as a conflict — moves a
    // record's real status without this list knowing. Refetch so cards cannot
    // sit on a stale status.
    ref.listen(queueChangedProvider, (_, _) => refresh());
    Future.microtask(refresh);
    return const OrdersState();
  }

  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);

  Future<void> refresh() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.userId.isEmpty) return;

    final requestId = ++_requestId;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final repository = ref.read(ordersRepositoryProvider);
      final page = await repository.listAll(session.userId);

      if (requestId != _requestId) return;
      state = state.copyWith(
        records: page.records,
        fromCache: page.fromCache,
        loading: false,
      );
    } on ApiFailure catch (e) {
      if (requestId != _requestId) return;
      state = state.copyWith(loading: false, error: e.message);
    }
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(
    sync: ref.watch(syncClientProvider),
    api: ref.watch(apiClientProvider),
  ),
);

final ordersControllerProvider =
    NotifierProvider<OrdersController, OrdersState>(OrdersController.new);
