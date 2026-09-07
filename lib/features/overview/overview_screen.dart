import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/maintenance_record.dart';
import '../../domain/technician_insights.dart';
import '../../state/overview_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import '../../widgets/tech_header.dart';

/// Analytics for the signed-in technician: one tab per maintenance type, each
/// showing what they have handled this year, what is open this month, and a
/// twelve-month bar chart.
class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  OrderType _tab = OrderType.workOrder;

  /// The chart fill per tab, matching `OverviewChart.tsx` exactly.
  static const _fill = {
    OrderType.workOrder: AppColors.blue600,
    OrderType.preventive: AppColors.emerald600,
    OrderType.reactive: AppColors.red600,
    OrderType.annual: AppColors.amber600,
  };

  static String _totalLabel(OrderType type) => switch (type) {
    OrderType.workOrder => 'Work Orders',
    OrderType.preventive => 'Preventive Tasks',
    OrderType.reactive => 'Reactive Requests',
    OrderType.annual => 'Annual Contracts',
  };

  static String _tabLabel(OrderType type) => switch (type) {
    OrderType.workOrder => 'Work Order',
    OrderType.preventive => 'Preventive',
    OrderType.reactive => 'Reactive',
    OrderType.annual => 'Annual',
  };

  static String _trendLabel(OrderType type) => switch (type) {
    OrderType.workOrder => 'Work Order Trends',
    OrderType.preventive => 'Preventive Trends',
    OrderType.reactive => 'Reactive Trends',
    OrderType.annual => 'Annual Trends',
  };

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(technicianInsightsProvider);
    final color = _fill[_tab]!;

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: const TechHeader(title: 'Analytics Overview'),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(technicianInsightsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TypeTabs(
              selected: _tab,
              onSelect: (type) => setState(() => _tab = type),
              label: _tabLabel,
            ),
            const SizedBox(height: 16),
            // The web page reads `insights.monthlyTrends` unguarded and shows
            // a blank screen when the fetch fails (§10 row 4). Here a failure
            // is a card that says so and can be pulled to retry.
            if (insights.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: TechSpinner(),
              )
            else if (insights.hasError)
              const TechEmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Could not load your figures',
                subtitle: 'Pull down to try again.',
              )
            else ...[
              _StatCard(
                title: _totalLabel(_tab),
                value: insights.requireValue.totalsFor(_tab).total,
                caption: 'This Year',
                accent: AppColors.green500,
                icon: LucideIcons.trendingUp,
                iconColor: AppColors.green600,
                iconBackground: AppColors.green50,
              ),
              const SizedBox(height: 16),
              _StatCard(
                title: 'Work In Progress',
                value: insights.requireValue.inProgressFor(_tab),
                caption: 'This Month',
                accent: AppColors.orange600,
                icon: LucideIcons.activity,
                iconColor: AppColors.orange600,
                iconBackground: AppColors.orange50,
              ),
              const SizedBox(height: 16),
              _TrendCard(
                title: _trendLabel(_tab),
                trends: insights.requireValue.monthlyTrends,
                type: _tab,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The four maintenance types, laid out as one row of equal segments.
class _TypeTabs extends StatelessWidget {
  const _TypeTabs({
    required this.selected,
    required this.onSelect,
    required this.label,
  });

  final OrderType selected;
  final ValueChanged<OrderType> onSelect;
  final String Function(OrderType) label;

  /// Web tab order — work order, reactive, preventive, annual — which is not
  /// the enum's own order, so it is written out.
  static const _order = [
    OrderType.workOrder,
    OrderType.reactive,
    OrderType.preventive,
    OrderType.annual,
  ];

  @override
  Widget build(BuildContext context) => TechCard(
    padding: const EdgeInsets.all(4),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(context.radii.lg),
      ),
      child: Row(
        children: [
          for (final type in _order)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: type == selected
                        ? AppColors.orange600
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: type == selected
                        ? FeElevation.tinted(AppColors.orange600)
                        : null,
                  ),
                  child: Text(
                    label(type),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: type == selected
                          ? AppColors.white
                          : AppColors.gray500,
                      fontWeight: type == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.accent,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
  });

  final String title;
  final int value;
  final String caption;
  final Color accent;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TechCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
              boxShadow: FeElevation.tinted(iconColor),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.gray500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$value',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.gray900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  caption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.gray400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.trends,
    required this.type,
    required this.color,
  });

  final String title;
  final List<MonthlyTrend> trends;
  final OrderType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TechCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.gray700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: trends.isEmpty
                ? Center(
                    child: Text(
                      'No activity recorded this year.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.gray500,
                      ),
                    ),
                  )
                : _TrendChart(trends: trends, type: type, color: color),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gray50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                // The endpoint always reports the current year off the server
                // clock, so the caption states which year rather than offering
                // a picker that cannot change anything.
                'Monthly Order Volume (${DateTime.now().year})',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.gray500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.trends,
    required this.type,
    required this.color,
  });

  final List<MonthlyTrend> trends;
  final OrderType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final counts = [for (final t in trends) t.countFor(type)];
    final peak = counts.fold<int>(0, (a, b) => a > b ? a : b);
    // A flat year of zeros would otherwise give the chart no range to draw in.
    final maxY = (peak == 0 ? 4 : peak * 1.25).toDouble();

    return BarChart(
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppColors.gray200,
            strokeWidth: 1,
            dashArray: [3, 3],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                // Only whole orders exist, so fractional gridline labels are
                // noise.
                if (value != value.roundToDouble()) {
                  return const SizedBox.shrink();
                }
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(
                    color: AppColors.gray500,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= trends.length) {
                  return const SizedBox.shrink();
                }
                final month = trends[index].month;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    // Node hands back "Sept", not "Sep", which is wide enough
                    // to run into its neighbours on a phone. Twelve labels
                    // across 570 px only fit at three characters.
                    month.length > 3 ? month.substring(0, 3) : month,
                    style: const TextStyle(
                      color: AppColors.gray500,
                      fontSize: 9,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.white,
            tooltipBorder: const BorderSide(color: AppColors.gray200),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
                  '${trends[groupIndex].month}\n',
                  const TextStyle(
                    color: AppColors.gray500,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()}',
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < trends.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    // Same hue the web uses for this tab — only the shading is
                    // new, so the "match the web" invariant on [color] holds.
                    colors: [color.withValues(alpha: 0.55), color],
                  ),
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
