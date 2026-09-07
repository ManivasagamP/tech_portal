import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/utils/checklist_status.dart';
import '../../core/utils/dates.dart';
import '../../domain/checklist.dart';
import '../../domain/maintenance_record.dart';
import '../../state/checklist_controller.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import 'checklist_item_sheet.dart';
import 'close_sheet.dart';

/// The row shows the text before the first colon, capped at 40 characters —
/// item names carry a long "task: detail" description.
String shortChecklistTitle(String title) {
  final head = title.contains(':') ? title.split(':').first.trim() : title;
  return head.length > 40 ? '${head.substring(0, 40)}…' : head;
}

class ChecklistTab extends ConsumerWidget {
  const ChecklistTab({super.key, required this.record, required this.orderKey});

  final MaintenanceRecord record;
  final OrderKey orderKey;

  Future<void> _openItem(BuildContext context, int index) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.white,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.radii.sheet),
          ),
        ),
        builder: (context) => ChecklistItemSheet(
          orderKey: orderKey,
          index: index,
          requireFaceCapture: record.requireFaceCapture,
          requireLocation: record.requireLocation,
        ),
      );

  Future<void> _addOther(BuildContext context, WidgetRef ref) async {
    final description = await showDialog<String>(
      context: context,
      builder: (context) => const _AddOtherDialog(),
    );
    if (description == null || description.isEmpty) return;

    final message = await ref
        .read(checklistControllerProvider(orderKey).notifier)
        .addOther(description);
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.text)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checklistControllerProvider(orderKey));
    final items = state.items;
    final summary = deriveChecklistSummary(items);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProgressHeader(summary: summary),
        const SizedBox(height: 16),
        if (items.isEmpty)
          const TechEmptyState(
            icon: LucideIcons.listChecks,
            title: 'No checklist items',
            subtitle: 'Add an "Other" task to record work done here.',
          )
        else
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChecklistRow(
                item: items[index],
                busy: state.busyIndex == index,
                onOpen: () => _openItem(context, index),
                onToggle: () async {
                  final message = await ref
                      .read(checklistControllerProvider(orderKey).notifier)
                      .toggle(index);
                  if (message != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(message.text)));
                  }
                },
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: state.addingOther ? null : () => _addOther(context, ref),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Add Other Task'),
        ),
        const SizedBox(height: 16),
        _CloseSection(items: items, record: record, orderKey: orderKey),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.summary});

  final ChecklistSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete =
        summary.totalCount > 0 && summary.completedCount == summary.totalCount;

    return TechCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: LucideIcons.circleCheck,
                style: context.accents.orange,
                size: 40,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checklist',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      complete ? 'All tasks completed' : 'Track progress',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.gray500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: complete
                      ? context.accents.emerald.background
                      : AppColors.gray50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${summary.completedCount}/${summary.totalCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: complete ? AppColors.emerald700 : AppColors.gray700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: summary.progress,
              minHeight: 8,
              backgroundColor: AppColors.gray100,
              valueColor: const AlwaysStoppedAnimation(AppColors.orange600),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            summary.state.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.gray600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.item,
    required this.busy,
    required this.onOpen,
    required this.onToggle,
  });

  final ChecklistItem item;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteCount =
        item.comments.length + (item.legacyComment == null ? 0 : 1);

    return TechCard(
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Checkbox(
                    value: item.isCompleted,
                    onChanged: (_) => onToggle(),
                    visualDensity: VisualDensity.compact,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        shortChecklistTitle(item.title),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: item.isCompleted
                              ? AppColors.gray400
                              : AppColors.gray900,
                        ),
                      ),
                    ),
                    if (item.isOther)
                      const _RowChip(
                        label: 'Other',
                        background: AppColors.slate100,
                        foreground: AppColors.slate700,
                      ),
                    if (item.isRunning)
                      const _RowChip(
                        label: 'Running…',
                        background: AppColors.amber50,
                        foreground: AppColors.amber900,
                        icon: LucideIcons.clock,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if ((item.timeSpent ?? 0) > 0)
                      _Meta(
                        icon: LucideIcons.clock,
                        label: formatMinutesAsHours(item.timeSpent!),
                      ),
                    if (item.attachments.isNotEmpty)
                      _Meta(
                        icon: LucideIcons.paperclip,
                        label: '${item.attachments.length}',
                      ),
                    if (noteCount > 0)
                      _Meta(
                        icon: LucideIcons.messageSquare,
                        label: '$noteCount',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: AppColors.gray400,
          ),
        ],
      ),
    );
  }
}

class _RowChip extends StatelessWidget {
  const _RowChip({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: foreground),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: foreground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppColors.gray400),
      const SizedBox(width: 4),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.gray500),
      ),
    ],
  );
}

/// Closing a record is the next phase. Until then this states what still
/// stands between the technician and being able to close it.
/// The end of the checklist: whether this job may be closed yet, and — once it
/// may — the manual-hours override and the button that opens the close sheet.
class _CloseSection extends ConsumerStatefulWidget {
  const _CloseSection({
    required this.items,
    required this.record,
    required this.orderKey,
  });

  final List<ChecklistItem> items;
  final MaintenanceRecord record;
  final OrderKey orderKey;

  @override
  ConsumerState<_CloseSection> createState() => _CloseSectionState();
}

class _CloseSectionState extends ConsumerState<_CloseSection> {
  final _hoursController = TextEditingController();

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _openCloseSheet() async {
    final hours = double.tryParse(_hoursController.text.trim());
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: AppColors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.radii.sheet),
        ),
      ),
      builder: (context) => CloseSheet(
        orderKey: widget.orderKey,
        record: widget.record,
        // Downtime starts when work started, which is the first checklist
        // timer — the record's own start date is only a fallback for the kinds
        // that persist one.
        predictedStart:
            getFirstChecklistStartTime(widget.items) ??
            widget.record.startedDate,
        manualHours: hours,
      ),
    );

    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mandatory = widget.record.isChecklistMandatory;

    // Mirrors the server's close guard: at least one item done — an "Other"
    // one counts — and, when the checklist is mandatory, every listed item.
    // This is UX only; the server enforces the real rule and its 422 wins.
    final canClose =
        hasAnyChecklistCompleted(widget.items) &&
        (!mandatory || isChecklistFullyComplete(widget.items));

    if (widget.record.completedDate != null) {
      return const TechCard(
        borderColor: AppColors.green200,
        child: Row(
          children: [
            Icon(LucideIcons.circleCheck, size: 18, color: AppColors.green600),
            SizedBox(width: 12),
            Expanded(child: Text('This job is closed.')),
          ],
        ),
      );
    }

    if (!canClose) {
      return TechCard(
        borderColor: AppColors.gray200,
        child: Row(
          children: [
            const Icon(LucideIcons.info, size: 18, color: AppColors.gray400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                mandatory
                    ? 'Complete every task before this job can be closed.'
                    : 'Complete at least one task before this job can be closed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.gray600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return TechCard(
      borderColor: AppColors.green200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.circleCheck,
                size: 18,
                color: AppColors.green600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This job is ready to close.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.gray700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Manual hours (optional)',
              hintText:
                  'Leave empty to use the tracked '
                  '${calculateChecklistsActualHours(widget.items)} hrs',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _openCloseSheet,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.emerald600,
            ),
            child: const Text('Completed Works'),
          ),
        ],
      ),
    );
  }
}

class _AddOtherDialog extends StatefulWidget {
  const _AddOtherDialog();

  @override
  State<_AddOtherDialog> createState() => _AddOtherDialogState();
}

class _AddOtherDialogState extends State<_AddOtherDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.white,
    title: const Text('Add other task'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLines: 3,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(hintText: 'Describe the work you did'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Add'),
      ),
    ],
  );
}
