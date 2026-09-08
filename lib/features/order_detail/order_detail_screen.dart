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
import '../../state/auth_controller.dart';
import '../../state/order_detail_controller.dart';
// import '../../theme/fe_colors.dart'; // only used by the hidden voice note sheet below
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import 'checklist_tab.dart';
import 'detail_widgets.dart';
// import 'record_voice_note.dart'; // only used by the hidden voice note sheet below
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

  static String detailTitleFor(MaintenanceRecord record) =>
      switch (record.type) {
        OrderType.workOrder => record.titleField ?? '',
        OrderType.preventive => record.assetName ?? 'Preventive Maintenance',
        OrderType.reactive =>
          firstNonEmpty([record.assetName, record.subRequest]) ??
              'Reactive Maintenance',
        OrderType.annual => record.assetName ?? 'Annual Maintenance',
      };

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  late final OrderKey _key = (
    type: OrderType.fromSlug(widget.orderType),
    id: widget.orderId,
  );

  @override
  void initState() {
    super.initState();
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
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF8FAFC),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              LucideIcons.arrowLeft,
              color: Color(0xFF0F172A),
              size: 22,
            ),
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
          title: Text(
            OrderDetailScreen.headerTitleFor(key.type),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          actions: [
            if (ref.watch(authControllerProvider).permissions.isAiAgent &&
                detail.hasValue)
              IconButton(
                tooltip: 'Ask about this order',
                icon: const Icon(
                  LucideIcons.sparkles,
                  color: Color(0xFF0F172A),
                  size: 20,
                ),
                onPressed: () => showOrderChatSheet(
                  context,
                  orderKey: key,
                  assetName: detail.requireValue.record.assetName,
                ),
              ),
            const SizedBox(width: 8),
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
          loading: () => const Center(child: TechSpinner()),
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
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF8FAFC),
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: const Color(0xFF0284C7),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13.5,
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

  static const _icons = {
    OrderType.workOrder: LucideIcons.wrench,
    OrderType.preventive: LucideIcons.shieldCheck,
    OrderType.reactive: LucideIcons.zap,
    OrderType.annual: LucideIcons.calendarCheck,
  };

  static const _iconColors = {
    OrderType.workOrder: Color(0xFF0284C7),
    OrderType.preventive: Color(0xFF10B981),
    OrderType.reactive: Color(0xFFEF4444),
    OrderType.annual: Color(0xFFF59E0B),
  };

  static const _badgeBgs = {
    OrderType.workOrder: Color(0xFFE0F2FE),
    OrderType.preventive: Color(0xFFDCFCE7),
    OrderType.reactive: Color(0xFFFFEEF1),
    OrderType.annual: Color(0xFFFEF3C7),
  };

  // Record voice note — hidden for now, along with its call site above.
  // void _showVoiceNoteSheet(BuildContext context, String? audioUrl) {
  //   showModalBottomSheet<void>(
  //     context: context,
  //     backgroundColor: FeColors.panel,
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  //     ),
  //     builder: (context) => SafeArea(
  //       child: Padding(
  //         padding: const EdgeInsets.all(20),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             const Text(
  //               'Record Voice Note',
  //               style: TextStyle(
  //                 fontSize: 18,
  //                 fontWeight: FontWeight.w800,
  //                 color: Color(0xFF0F172A),
  //               ),
  //             ),
  //             const SizedBox(height: 14),
  //             RecordVoiceNote(
  //               orderKey: orderKey,
  //               audioUrl: audioUrl,
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = detail.record;
    final permissions = ref.watch(authControllerProvider).permissions;
    final iconData = _icons[record.type] ?? LucideIcons.wrench;
    final iconColor = _iconColors[record.type] ?? const Color(0xFF0284C7);
    final badgeBg = _badgeBgs[record.type] ?? const Color(0xFFE0F2FE);

    return RefreshIndicator(
      onRefresh: ref
          .read(orderDetailControllerProvider(orderKey).notifier)
          .refresh,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Hero Order Identity Card with soft airy cyan/sky blue gradient
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Colors.white,
                  Color(0xFFEFF6FF),
                  Color(0xFFE0F2FE),
                ],
                stops: [0.0, 0.45, 0.75, 1.0],
              ),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(iconData, size: 22, color: iconColor),
                    ),
                    if (record.priority != null && record.priority!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          record.priority!,
                          style: const TextStyle(
                            color: Color(0xFFD97706),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  OrderDetailScreen.detailTitleFor(record),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  record.referenceId ?? '',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _ActionPillButton(
                        icon: LucideIcons.box,
                        label: 'View in 3D',
                        onTap: () {
                          if (record.assetId != null) {
                            context.push(
                              '${Routes.twin(record.assetId!)}?name=${Uri.encodeComponent(OrderDetailScreen.detailTitleFor(record))}',
                            );
                          }
                        },
                      ),
                    ),
                    // Record voice note — hidden for now.
                    // const SizedBox(width: 12),
                    // Expanded(
                    //   child: _ActionPillButton(
                    //     icon: LucideIcons.mic,
                    //     label: 'Record voice note',
                    //     onTap: () => _showVoiceNoteSheet(context, record.notesAudioUrl),
                    //   ),
                    // ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Time Tracker / Checklist Summary Card
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
          const SizedBox(height: 14),

          // Assignment Invite Panel if pending
          AssignmentInvitePanel(
            record: record,
            respond: ({required accept, reason}) => ref
                .read(orderDetailControllerProvider(orderKey).notifier)
                .respondToInvite(accept: accept, reason: reason),
          ),

          // Metadata Information Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _MetaItemRow(
                  icon: LucideIcons.mapPin,
                  label: 'Location',
                  value:
                      record.location ??
                      'Fusion Eco Tower A - Ground Floor - Main Reception',
                ),
                const Divider(height: 28, color: Color(0xFFF1F5F9)),
                _MetaItemRow(
                  icon: LucideIcons.calendar,
                  label: 'Due Date',
                  value: _dateValueFor(record),
                ),
                const Divider(height: 28, color: Color(0xFFF1F5F9)),
                _MetaItemRow(
                  icon: LucideIcons.user,
                  label: 'Assigned To',
                  value:
                      record.technicianName != null &&
                          record.technicianName!.isNotEmpty
                      ? record.technicianName!
                      : 'Balaji',
                ),
                if (record.type == OrderType.annual &&
                    record.contractValue != null) ...[
                  const Divider(height: 28, color: Color(0xFFF1F5F9)),
                  _MetaItemRow(
                    icon: LucideIcons.banknote,
                    label: 'Contract Value',
                    value: formatCurrencyFromBase(
                      record.contractValue,
                      permissions,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Description Card
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.fileText,
                        size: 18,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  record.description != null && record.description!.isNotEmpty
                      ? record.description!
                      : 'Replace the AC unit filter as per maintenance manual.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _dateValueFor(MaintenanceRecord record) {
    if (record.type == OrderType.annual) {
      final start = asDate(record.raw['startDate']);
      final end = asDate(record.raw['endDate']);
      if (start != null && end != null) {
        return '${formatDate(start)} – ${formatDate(end)}';
      }
    }
    return record.effectiveDate == null
        ? 'Jan 20, 2024'
        : formatDate(record.effectiveDate!);
  }
}

class _ActionPillButton extends StatelessWidget {
  const _ActionPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.97,
      child: Material(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: const Color(0xFF0284C7)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0284C7),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaItemRow extends StatelessWidget {
  const _MetaItemRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
