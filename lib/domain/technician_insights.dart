import '../core/network/envelope.dart';
import 'maintenance_record.dart';

/// One month's bar in the overview chart. The server sends all twelve months
/// of the current year, zeros included, so the chart never has holes.
class MonthlyTrend {
  const MonthlyTrend({
    required this.month,
    required this.workOrder,
    required this.preventive,
    required this.reactive,
    required this.annual,
  });

  /// Short English month name — "Jan", "Feb" — built server-side with
  /// `toLocaleString("default", { month: "short" })`.
  final String month;
  final int workOrder;
  final int preventive;
  final int reactive;
  final int annual;

  int countFor(OrderType type) => switch (type) {
        OrderType.workOrder => workOrder,
        OrderType.preventive => preventive,
        OrderType.reactive => reactive,
        OrderType.annual => annual,
      };

  factory MonthlyTrend.fromJson(Map<String, dynamic> json) => MonthlyTrend(
        month: json['month']?.toString() ?? '',
        workOrder: asInt(json['workOrder']) ?? 0,
        preventive: asInt(json['preventive']) ?? 0,
        reactive: asInt(json['reactive']) ?? 0,
        annual: asInt(json['annual']) ?? 0,
      );
}

/// Year-to-date count and cost for one maintenance type.
class YearToDateTotals {
  const YearToDateTotals({this.total = 0, this.cost = 0});

  final int total;
  final double cost;

  factory YearToDateTotals.fromJson(dynamic json) {
    if (json is! Map) return const YearToDateTotals();
    return YearToDateTotals(
      total: asInt(json['total']) ?? 0,
      cost: asDouble(json['cost']) ?? 0,
    );
  }
}

/// `GET /api/analytics/technician/:id/insights`.
///
/// Every field is optional on the wire and every fallback is a zero rather
/// than a null: the web page reads straight through `insights.monthlyTrends`
/// and throws a white screen the moment the fetch fails (§10 row 4). Parsing
/// defensively here means a partial response degrades to empty cards.
class TechnicianInsights {
  const TechnicianInsights({
    this.yearToDate = const {},
    this.inProgress = const {},
    this.monthlyTrends = const [],
  });

  final Map<OrderType, YearToDateTotals> yearToDate;
  final Map<OrderType, int> inProgress;
  final List<MonthlyTrend> monthlyTrends;

  YearToDateTotals totalsFor(OrderType type) =>
      yearToDate[type] ?? const YearToDateTotals();

  int inProgressFor(OrderType type) => inProgress[type] ?? 0;

  bool get isEmpty => monthlyTrends.isEmpty && yearToDate.isEmpty;

  /// The response keys are not the path slugs — work orders are `workOrders`
  /// here but `work-order` everywhere else — so the mapping is spelled out
  /// rather than derived, the same way [OrderType]'s other vocabularies are.
  static const _insightKey = {
    OrderType.workOrder: 'workOrders',
    OrderType.preventive: 'preventive',
    OrderType.reactive: 'reactive',
    OrderType.annual: 'annual',
  };

  factory TechnicianInsights.fromJson(Map<String, dynamic> json) {
    final ytdRaw = json['yearToDate'];
    final progressRaw = json['inProgress'];
    final trendsRaw = json['monthlyTrends'];

    return TechnicianInsights(
      yearToDate: {
        for (final entry in _insightKey.entries)
          entry.key: YearToDateTotals.fromJson(
            ytdRaw is Map ? ytdRaw[entry.value] : null,
          ),
      },
      inProgress: {
        for (final entry in _insightKey.entries)
          entry.key: progressRaw is Map
              ? (asInt(progressRaw[entry.value]) ?? 0)
              : 0,
      },
      monthlyTrends: trendsRaw is List
          ? trendsRaw
              .whereType<Map>()
              .map((row) => MonthlyTrend.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
    );
  }
}
