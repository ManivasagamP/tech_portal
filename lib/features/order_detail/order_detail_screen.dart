import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/network/envelope.dart';
import '../../core/utils/checklist_status.dart';
import '../../core/utils/currency.dart';
import '../../core/utils/dates.dart';
import '../../domain/maintenance_record.dart';
import '../../core/storage/session_store.dart';
import '../../state/auth_controller.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import 'checklist_tab.dart';
import 'detail_widgets.dart';
import 'record_voice_note.dart';
import 'history_tab.dart';
import 'order_chat_sheet.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderType,
    required this.orderId,
  });

  final String orderType;
  final String orderId;

  static String headerTitleFor(OrderType type) => switch (type) {
        OrderType.workOrder => 'Work Order Details',
        OrderType.preventive => 'Preventive Maintenance',
        OrderType.reactive => 'Reactive Maintenance',
        OrderType.annual => 'Annual Maintenance',
      };

  /// The detail heading uses its own per-type fallbacks, distinct from both the
  /// card and the dashboard chains.
  static String detailTitleFor(MaintenanceRecord record) => switch (record.type) {
        OrderType.workOrder => record.titleField ?? '',
        OrderType.preventive =>
          record.assetName ?? 'Preventive Maintenance',
        OrderType.reactive =>
          firstNonEmpty([record.assetName, record.subRequest]) ??
              'Reactive Maintenance',
        OrderType.annual => record.assetName ?? 'Annual Maintenance',
      };

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  late final OrderKey _key =
      (type: OrderType.fromSlug(widget.orderType), id: widget.orderId);

  @override
  void initState() {
    super.initState();
    // The record controller lives for the whole session, so a job opened once
    // keeps whatever it loaded then. Reopening it has to go back to the server
    // — a supervisor may have accepted it, reassigned it or changed its
    // priority since, and none of that would show otherwise.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orderDetailControllerProvider(_key).notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final detail = ref.watch(orderDetailControllerProvider(key));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.gray50,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          foregroundColor: FeLightAppBar.foreground,
          titleTextStyle: FeLightAppBar.title(context),
          systemOverlayStyle: FeLightAppBar.overlay,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            onPressed: () => context.pop(),
          ),
          title: Text(OrderDetailScreen.headerTitleFor(key.type)),
          actions: [
            // Gated on the account flag, exactly as the web widget is: without
            // it the assistant is not part of this technician's portal at all.
            if (ref.watch(authControllerProvider).permissions.isAiAgent &&
                detail.hasValue)
              IconButton(
                tooltip: 'Ask about this order',
                icon: const Icon(LucideIcons.sparkles, size: 18),
                onPressed: () => showOrderChatSheet(
                  context,
                  orderKey: key,
                  assetName: detail.requireValue.record.assetName,
                ),
              ),
          ],
          bottom: detail.hasValue
              ? _DetailTabBar(
                  tasksLabel: key.type == OrderType.workOrder
                      ? 'Tasks (${detail.requireValue.record.checklists.length})'
                      : 'Checklist',
                )
              : null,
        ),
        body: detail.when(
          loading: () => const TechSpinner(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: TechEmptyState(
              icon: LucideIcons.circleAlert,
              title: 'Order not found',
              subtitle: '$error',
            ),
          ),
          data: (data) => TabBarView(
            children: [
              _DetailsTab(detail: data, orderKey: key),
              ChecklistTab(record: data.record, orderKey: key),
              HistoryTab(orderKey: key),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _DetailTabBar({required this.tasksLabel});

  final String tasksLabel;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.white,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(context.radii.card),
          ),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: AppColors.orange600,
              borderRadius: BorderRadius.circular(context.radii.lg),
              boxShadow: FeElevation.sm,
            ),
            labelColor: AppColors.white,
            unselectedLabelColor: AppColors.gray500,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              const Tab(text: 'Details'),
              Tab(text: tasksLabel),
              const Tab(text: 'History'),
            ],
          ),
        ),
      );
}

class _DetailsTab extends ConsumerWidget {
  const _DetailsTab({required this.detail, required this.orderKey});

  final OrderDetail detail;
  final OrderKey orderKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = detail.record;
    final theme = Theme.of(context);
    final permissions = ref.watch(authControllerProvider).permissions;
    final priorityStyle = context.chips.priorityOnDetail(record.priority);

    return RefreshIndicator(
      onRefresh: ref.read(orderDetailControllerProvider(orderKey).notifier).refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TechCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            OrderDetailScreen.detailTitleFor(record),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            record.referenceId ?? '',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.gray600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityStyle.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        record.priority ?? '',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: priorityStyle.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (record.assetId != null)
                  _ViewInTwinButton(
                    assetId: record.assetId!,
                    assetName: OrderDetailScreen.detailTitleFor(record),
                  ),
                if (record.type == OrderType.workOrder) ...[
                  const SizedBox(height: 16),
                  RecordVoiceNote(
                    orderKey: orderKey,
                    audioUrl: record.notesAudioUrl,
                  ),
                ],
                const SizedBox(height: 24),
                if (record.type == OrderType.workOrder)
                  TimeTrackerCard(
                    startedDate: record.startedDate,
                    completedDate: record.completedDate,
                    actualHours: record.actualHours,
                    queuedComplete: detail.queuedComplete,
                  )
                else
                  ChecklistSummaryCard(
                    summary: deriveChecklistSummary(record.checklists),
                  ),
                const SizedBox(height: 24),
                AssignmentInvitePanel(
                  record: record,
                  respond: ({required accept, reason}) => ref
                      .read(orderDetailControllerProvider(orderKey).notifier)
                      .respondToInvite(accept: accept, reason: reason),
                ),
                DetailMetaRow(
                  icon: LucideIcons.mapPin,
                  text: record.location ?? 'No location',
                ),
                ..._dateRows(record),
                if (record.technicianName != null)
                  DetailMetaRow(
                    icon: LucideIcons.user,
                    text: record.technicianName!,
                  ),
                if (record.type == OrderType.annual &&
                    record.contractValue != null)
                  DetailMetaRow(
                    icon: LucideIcons.banknote,
                    text: 'Value: '
                        '${formatCurrencyFromBase(record.contractValue, permissions)}',
                  ),
                if (record.description != null &&
                    record.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.gray200),
                  const SizedBox(height: 16),
                  Text(
                    'Description',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.gray700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    record.description!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.gray600),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.gray200),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DetailFact(
                        label: 'Status',
                        value: record.status ?? '',
                      ),
                    ),
                    Expanded(child: _secondFact(record, permissions)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Each kind labels its own date field, and annual carries two.
  List<Widget> _dateRows(MaintenanceRecord record) {
    String render(DateTime? date) =>
        date == null ? 'No date' : formatDate(date);

    return switch (record.type) {
      OrderType.workOrder => [
          DetailMetaRow(
            icon: LucideIcons.calendar,
            text: 'Due: '
                '${record.effectiveDate == null ? 'No due date' : formatDate(record.effectiveDate!)}',
          ),
        ],
      OrderType.preventive => [
          DetailMetaRow(
            icon: LucideIcons.calendar,
            text: 'Planned: ${render(record.effectiveDate)}',
          ),
        ],
      OrderType.reactive => [
          DetailMetaRow(
            icon: LucideIcons.calendar,
            text: 'Scheduled: ${render(record.effectiveDate)}',
          ),
        ],
      // `startDate`/`endDate` are read straight off the row: the server does
      // not expose them as columns today, so both render "No date".
      OrderType.annual => [
          DetailMetaRow(
            icon: LucideIcons.calendar,
            text: 'Start: ${render(asDate(record.raw['startDate']))}',
          ),
          DetailMetaRow(
            icon: LucideIcons.calendar,
            text: 'End: ${render(asDate(record.raw['endDate']))}',
          ),
        ],
    };
  }

  Widget _secondFact(MaintenanceRecord record, Permissions permissions) =>
      switch (record.type) {
        OrderType.workOrder => DetailFact(
            label: 'Estimated Hours',
            value: '${record.estimatedHours ?? 0} hrs',
          ),
        OrderType.preventive => DetailFact(
            label: 'Frequency',
            value: record.frequency ?? 'N/A',
          ),
        OrderType.reactive => DetailFact(
            label: 'Urgency',
            value: record.urgency ?? 'Normal',
          ),
        OrderType.annual => DetailFact(
            label: 'Contract Value',
            value: formatCurrencyFromBase(record.contractValue, permissions),
          ),
      };
}

class _ViewInTwinButton extends StatelessWidget {
  const _ViewInTwinButton({required this.assetId, required this.assetName});

  final String assetId;
  final String assetName;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => context.push(
            '${Routes.twin(assetId)}?name=${Uri.encodeComponent(assetName)}',
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: AppColors.orange50,
            foregroundColor: AppColors.orange700,
            side: const BorderSide(color: AppColors.orange200),
          ),
          icon: const Icon(LucideIcons.box, size: 16),
          label: const Text('View in 3D'),
        ),
      );
}
