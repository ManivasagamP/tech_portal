import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/utils/dates.dart';
import '../../domain/history_entry.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';

/// The web renders this as a desktop data table; on a phone it is a timeline.
class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key, required this.orderKey});

  final OrderKey orderKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(orderHistoryProvider(orderKey));

    return history.when(
      loading: () => const TechSpinner(),
      error: (error, _) => const Padding(
        padding: EdgeInsets.all(16),
        child: TechEmptyState(
          icon: LucideIcons.triangleAlert,
          title: 'Failed to load history',
        ),
      ),
      data: (entries) => entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: TechEmptyState(
                icon: LucideIcons.history,
                title: 'No history yet',
                subtitle: 'Changes to this record will appear here.',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _HistoryRow(entry: entries[index]),
            ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

  static (IconData, Color, Color) _styleFor(String action) => switch (action) {
        'CREATED' => (LucideIcons.fileText, AppColors.blue100, AppColors.blue700),
        'STATUS_UPDATE' => (
            LucideIcons.circleCheck,
            AppColors.green100,
            AppColors.green700
          ),
        'CHECKLIST_UPDATED' => (
            LucideIcons.circleCheck,
            AppColors.purple100,
            AppColors.purple700
          ),
        'DETAILS_UPDATED' => (
            LucideIcons.pencil,
            AppColors.orange100,
            AppColors.orange700
          ),
        'ASSIGNMENT_UPDATED' => (
            LucideIcons.user,
            AppColors.indigo100,
            AppColors.indigo700
          ),
        'SCHEDULE_UPDATED' => (
            LucideIcons.calendar,
            AppColors.yellow100,
            AppColors.yellow700
          ),
        'PRIORITY_UPDATED' => (
            LucideIcons.triangleAlert,
            AppColors.red100,
            AppColors.red700
          ),
        _ => (LucideIcons.layers, AppColors.slate100, AppColors.slate700),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, background, foreground) = _styleFor(entry.action);

    return TechCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: foreground),
                    const SizedBox(width: 4),
                    Text(
                      entry.actionLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (entry.timestamp != null)
                Text(
                  formatHistoryTimestamp(entry.timestamp!),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.gray500),
                ),
            ],
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.gray700),
            ),
          ],
          if (entry.hasValueChange) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    entry.oldValue?.isNotEmpty == true ? entry.oldValue! : '—',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.gray500,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(LucideIcons.arrowRight,
                      size: 12, color: AppColors.gray400),
                ),
                Flexible(
                  child: Text(
                    entry.newValue?.isNotEmpty == true ? entry.newValue! : '—',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.gray900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(LucideIcons.user, size: 12, color: AppColors.gray400),
              const SizedBox(width: 4),
              Text(
                entry.performedByRole == null
                    ? entry.userName
                    : '${entry.userName} · ${entry.performedByRole}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.gray500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
