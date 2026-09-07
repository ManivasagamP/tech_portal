import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../domain/maintenance_record.dart';
import '../../state/orders_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import '../../widgets/order_card.dart';
import '../../widgets/tech_header.dart';
import 'filter_sheet.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters(OrdersState state) async {
    final result = await showModalBottomSheet<OrderFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
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

    // Filters reset on a type switch, so the search box has to follow. This
    // has to run outside build — clearing the controller there would mark the
    // TextField dirty mid-build.
    ref.listen(ordersControllerProvider.select((s) => s.searchQuery), (
      _,
      query,
    ) {
      if (query.isEmpty && _searchController.text.isNotEmpty) {
        _searchController.clear();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: const TechHeader(title: 'Orders', showNotifications: false),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TechCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Maintenance Type',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.gray700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<OrderType?>(
                    initialValue: state.selectedType,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<OrderType?>(
                        value: null,
                        child: Text('All Tasks'),
                      ),
                      for (final type in kBrowsableOrderTypes)
                        DropdownMenuItem<OrderType?>(
                          value: type,
                          child: Text(type.label),
                        ),
                    ],
                    onChanged: controller.selectType,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: controller.setSearchQuery,
                    decoration: InputDecoration(
                      hintText: 'Search orders...',
                      prefixIcon: const Icon(LucideIcons.search, size: 16),
                      suffixIcon: state.searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(LucideIcons.x, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                controller.setSearchQuery('');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openFilters(state),
                  icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
                  label: const Text('Filters'),
                ),
              ],
            ),
            if (state.hasAnyFilter) ...[
              const SizedBox(height: 16),
              _ActiveFilters(state: state, onClearAll: _clearAll),
            ],
            const SizedBox(height: 16),
            if (state.loading && state.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: TechSpinner(),
              )
            else if (state.error != null && state.records.isEmpty)
              TechEmptyState(
                icon: LucideIcons.triangleAlert,
                title: 'Failed to load orders',
                subtitle: state.error,
              )
            else if (visible.isEmpty)
              const TechEmptyState(
                icon: LucideIcons.clipboardList,
                title: 'No orders found',
                subtitle: 'Try adjusting your filters',
              )
            else
              for (final record in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
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
          ],
        ),
      ),
    );
  }
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
        Text(
          'Active filters:',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.gray600),
        ),
        if (filters.priority != null)
          _FilterPill(
            label: 'Priority: ${filters.priority}',
            background: AppColors.orange100,
            foreground: AppColors.orange700,
          ),
        if (filters.status != null)
          _FilterPill(
            label: 'Status: ${filters.status}',
            background: AppColors.green100,
            foreground: AppColors.green700,
          ),
        if (filters.dateFilter != DateFilter.all)
          _FilterPill(
            label: filters.dateFilter == DateFilter.overdue
                ? 'Overdue'
                : 'Due Today',
            background: AppColors.purple100,
            foreground: AppColors.purple700,
          ),
        if (state.searchQuery.isNotEmpty)
          _FilterPill(
            label: 'Search: ${state.searchQuery}',
            background: AppColors.gray100,
            foreground: AppColors.gray700,
          ),
        GestureDetector(
          onTap: onClearAll,
          child: Text(
            'Clear all',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.red600,
              fontWeight: FontWeight.w500,
            ),
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
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: foreground),
    ),
  );
}
