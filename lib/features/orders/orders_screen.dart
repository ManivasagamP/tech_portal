import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../state/orders_controller.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/order_card.dart';
import 'filter_sheet.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _searchController = TextEditingController();
  bool _showSearchBar = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters(OrdersState state) async {
    final result = await showModalBottomSheet<OrderFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FeColors.panel,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.radii.sheet),
        ),
      ),
      builder: (context) => FilterSheet(
        filters: state.filters,
        statusOptions: statusOptionsFor(state.selectedType),
      ),
    );
    if (result != null) {
      ref.read(ordersControllerProvider.notifier).applyFilters(result);
    }
  }

  void _clearAll() {
    _searchController.clear();
    ref.read(ordersControllerProvider.notifier).resetFilters();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersControllerProvider);
    final controller = ref.read(ordersControllerProvider.notifier);
    final visible = state.visibleRecords;

    ref.listen(ordersControllerProvider.select((s) => s.searchQuery), (
      _,
      query,
    ) {
      if (query.isEmpty && _searchController.text.isNotEmpty) {
        _searchController.clear();
      }
    });

    return Scaffold(
      backgroundColor: FeColors.page,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Top Bar with Orders title, subtitle, Calendar, and Search circular action buttons
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'orders.title'.getString(context),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: FeColors.ink,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'orders.subtitle'.getString(context),
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: FeColors.ink2,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CircleActionButton(
                    icon: LucideIcons.calendarDays,
                    tooltip: 'common.calendar'.getString(context),
                    onTap: () => context.push(Routes.calendar),
                  ),
                  const SizedBox(width: 8),
                  _CircleActionButton(
                    icon: _showSearchBar ? LucideIcons.x : LucideIcons.search,
                    tooltip: 'common.search'.getString(context),
                    onTap: () {
                      setState(() {
                        _showSearchBar = !_showSearchBar;
                        if (!_showSearchBar) {
                          _searchController.clear();
                          controller.setSearchQuery('');
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Expandable Search & Filter Bar
              if (_showSearchBar) ...[
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: FeColors.panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: controller.setSearchQuery,
                          decoration: InputDecoration(
                            hintText: 'orders.search_hint'.getString(context),
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            suffixIcon: state.searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(LucideIcons.x, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      controller.setSearchQuery('');
                                    },
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: FeColors.panel,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openFilters(state),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.slidersHorizontal,
                                size: 17,
                                color: Color(0xFF475569),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'orders.filters'.getString(context),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              if (state.hasAnyFilter) ...[
                _ActiveFilters(state: state, onClearAll: _clearAll),
                const SizedBox(height: 14),
              ],

              // Diagnostic, not blocking: some kinds failed on the last "All
              // Tasks" fetch (state.orders_controller.dart merges each
              // OrdersPage.failedTypes straight through) but whatever did
              // load is still shown below — this only tells the technician
              // the empty-looking gaps might not be real.
              if (state.failedTypes.isNotEmpty) ...[
                const _PartialLoadBanner(),
                const SizedBox(height: 14),
              ],

              if (state.loading && state.records.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: TechSpinner(),
                )
              else if (state.error != null && state.records.isEmpty)
                TechEmptyState(
                  icon: LucideIcons.triangleAlert,
                  title: 'orders.load_failed'.getString(context),
                  subtitle: state.error,
                )
              else if (visible.isEmpty)
                TechEmptyState(
                  icon: LucideIcons.clipboardList,
                  title: 'orders.empty_title'.getString(context),
                  subtitle: 'orders.empty_subtitle'.getString(context),
                )
              else
                for (final record in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: OrderCard(
                      id: record.id,
                      type: record.type,
                      referenceId: record.referenceId ?? '',
                      title: record.cardTitle,
                      description: record.cardDescription,
                      priority: record.displayPriority,
                      status: record.displayStatus,
                      dueDate: record.effectiveDate,
                      technician: record.technicianName,
                      onTap: () => context.push(
                        Routes.orderDetail(
                          (state.selectedType ?? record.type).slug,
                          record.id,
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FeColors.panel,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 19, color: FeColors.ink),
        ),
      ),
    );
  }
}

/// Non-blocking notice that one or more order kinds failed to load on the
/// last "All Tasks" fetch (see OrdersRepository.listAll's `failedTypes` and
/// OrdersController.refresh). Whatever kinds *did* load are still rendered
/// below this — this exists purely so an all-empty or partial list reads as
/// "something failed" rather than being indistinguishable from a technician
/// who genuinely has zero assigned work.
class _PartialLoadBanner extends StatelessWidget {
  const _PartialLoadBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: FeColors.warningSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.triangleAlert, size: 16, color: FeColors.warning),
        const SizedBox(width: 8),
        Expanded(
          child: AppText.bodySmall(
            'orders.partial_load_failed'.getString(context),
            color: FeColors.warning,
            weight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.state, required this.onClearAll});

  final OrdersState state;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final filters = state.filters;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppText.bodySmall(
          'orders.active_filters_label'.getString(context),
          color: FeColors.ink2,
        ),
        if (filters.priority != null)
          _FilterPill(
            label: context.formatString(
              'orders.filter_priority'.getString(context),
              [filters.priority],
            ),
            background: FeColors.primary.withValues(alpha: 0.1),
            foreground: FeColors.primary,
          ),
        if (filters.status != null)
          _FilterPill(
            label: context.formatString(
              'orders.filter_status'.getString(context),
              [filters.status],
            ),
            background: FeColors.successSoft,
            foreground: FeColors.success,
          ),
        if (filters.dateFilter != DateFilter.all)
          _FilterPill(
            label: filters.dateFilter == DateFilter.overdue
                ? 'orders.overdue'.getString(context)
                : 'orders.due_today'.getString(context),
            background: FeColors.dashboardAccentSoft,
            foreground: FeColors.dashboardAccent,
          ),
        if (state.searchQuery.isNotEmpty)
          _FilterPill(
            label: context.formatString(
              'orders.filter_search'.getString(context),
              [state.searchQuery],
            ),
            background: FeColors.page,
            foreground: FeColors.ink2,
          ),
        GestureDetector(
          onTap: onClearAll,
          child: AppText.bodySmall(
            'orders.clear_all'.getString(context),
            color: FeColors.danger,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: AppText.bodySmall(
      label,
      color: foreground,
    ),
  );
}
