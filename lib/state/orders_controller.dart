import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/network/envelope.dart';
import '../data/orders_repository.dart';
import '../domain/maintenance_record.dart';
import 'auth_controller.dart';
import 'providers.dart';

enum SortOrder { desc, asc }

enum DateFilter { all, overdue, dueToday }

class OrderFilters {
  const OrderFilters({
    this.sortOrder = SortOrder.desc,
    this.dateFilter = DateFilter.all,
    this.priority,
    this.status,
  });

  final SortOrder sortOrder;
  final DateFilter dateFilter;
  final String? priority;
  final String? status;

  bool get isActive =>
      priority != null || status != null || dateFilter != DateFilter.all;

  OrderFilters copyWith({
    SortOrder? sortOrder,
    DateFilter? dateFilter,
    String? priority,
    String? status,
    bool clearPriority = false,
    bool clearStatus = false,
  }) =>
      OrderFilters(
        sortOrder: sortOrder ?? this.sortOrder,
        dateFilter: dateFilter ?? this.dateFilter,
        priority: clearPriority ? null : (priority ?? this.priority),
        status: clearStatus ? null : (status ?? this.status),
      );
}

class OrdersState {
  const OrdersState({
    this.selectedType,
    this.filters = const OrderFilters(),
    this.searchQuery = '',
    this.records = const [],
    this.loading = false,
    this.fromCache = false,
    this.error,
    this.failedTypes = const [],
  });

  /// Null is the "All Tasks" selection.
  final OrderType? selectedType;
  final OrderFilters filters;
  final String searchQuery;
  final List<MaintenanceRecord> records;
  final bool loading;
  final bool fromCache;
  final String? error;

  /// Kinds that failed to load on the last "All Tasks" fetch — see
  /// [OrdersPage.failedTypes]. Always empty for a single-type selection: a
  /// `listByType` failure surfaces through [error] instead, since there's
  /// only one kind in flight and nothing partial to report.
  final List<OrderType> failedTypes;

  bool get hasAnyFilter => filters.isActive || searchQuery.isNotEmpty;

  OrdersState copyWith({
    OrderType? selectedType,
    OrderFilters? filters,
    String? searchQuery,
    List<MaintenanceRecord>? records,
    bool? loading,
    bool? fromCache,
    String? error,
    List<OrderType>? failedTypes,
    bool clearType = false,
    bool clearError = false,
  }) =>
      OrdersState(
        selectedType: clearType ? null : (selectedType ?? this.selectedType),
        filters: filters ?? this.filters,
        searchQuery: searchQuery ?? this.searchQuery,
        records: records ?? this.records,
        loading: loading ?? this.loading,
        fromCache: fromCache ?? this.fromCache,
        error: clearError ? null : (error ?? this.error),
        failedTypes: failedTypes ?? this.failedTypes,
      );

  /// Priority → status → timeframe → search → sort, in the web's order.
  List<MaintenanceRecord> get visibleRecords {
    var result = records;

    final priority = filters.priority?.toLowerCase();
    if (priority != null) {
      result = result
          .where((r) => (r.priority ?? '').toLowerCase() == priority)
          .toList();
    }

    final status = filters.status?.toLowerCase().replaceFirst('-', ' ');
    if (status != null) {
      result = result.where((r) => r.normalizedStatus == status).toList();
    }

    if (filters.dateFilter != DateFilter.all) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      result = result.where((r) {
        final due = r.effectiveDate;
        if (due == null) return false;
        final day = DateTime(due.year, due.month, due.day);
        if (filters.dateFilter == DateFilter.overdue) {
          final s = r.normalizedStatus;
          final isFinished =
              s == 'completed' || s == 'cancelled' || s == 'expired';
          return day.isBefore(today) && !isFinished;
        }
        return day == today;
      }).toList();
    }

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
      return filters.sortOrder == SortOrder.asc
          ? dateA.compareTo(dateB)
          : dateB.compareTo(dateA);
    });
    return sorted;
  }
}

/// Status options offered by the filter sheet, per selected type.
List<String> statusOptionsFor(OrderType? type) => switch (type) {
      OrderType.workOrder => const [
          'Open',
          'In Progress',
          'On Hold',
          'Completed',
          'Cancelled',
        ],
      OrderType.reactive => const [
          'New',
          'In Progress',
          'Completed',
          'Cancelled',
        ],
      OrderType.annual => const [
          'Active',
          'Expired',
          'Cancelled',
          'Pending Renewal',
        ],
      OrderType.preventive => const [],
      null => const [
          'Open',
          'New',
          'In Progress',
          'On Hold',
          'Completed',
          'Cancelled',
          'Active',
          'Expired',
        ],
    };

class OrdersController extends Notifier<OrdersState> {
  /// A type switch does not cancel the fetch already in flight, and the "All"
  /// branch is three parallel requests — visibly the slowest. Without this a
  /// stale "All" response could land last and overwrite the filtered list the
  /// technician actually asked for.
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

  /// Filters reset on a type switch: status options are per-type, so keeping
  /// them would silently filter everything out.
  void selectType(OrderType? type) {
    state = state.copyWith(
      selectedType: type,
      clearType: type == null,
      filters: const OrderFilters(),
      searchQuery: '',
    );
    refresh();
  }

  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);

  void applyFilters(OrderFilters filters) =>
      state = state.copyWith(filters: filters);

  void resetFilters() => state = state.copyWith(
        filters: const OrderFilters(),
        searchQuery: '',
      );

  Future<void> refresh() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.userId.isEmpty) return;

    final requestId = ++_requestId;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final repository = ref.read(ordersRepositoryProvider);
      final type = state.selectedType;
      final page = type == null
          ? await repository.listAll(session.userId)
          : await repository.listByType(type, session.userId);

      if (requestId != _requestId) return;
      state = state.copyWith(
        records: page.records,
        fromCache: page.fromCache,
        loading: false,
        // Always overwritten (not merged) so switching away from "All
        // Tasks" — or a clean retry of it — clears a stale banner rather
        // than leaving yesterday's failure pinned to the screen.
        failedTypes: page.failedTypes,
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
