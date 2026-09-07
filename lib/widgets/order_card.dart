import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/utils/dates.dart';
import '../domain/maintenance_record.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extensions.dart';
import 'motion.dart';

/// The list row shared by the dashboard, orders list and calendar. Title and
/// description are passed in rather than read off the record, because the
/// screens deliberately use different fallback chains for the title.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.referenceId,
    required this.id,
    required this.title,
    required this.priority,
    this.type,
    this.description,
    this.status,
    this.dueDate,
    this.technician,
    this.onTap,
  });

  final String referenceId;
  final String id;
  final String title;
  final String priority;

  /// Drives the leading icon badge. Optional only because a handful of call
  /// sites predate it; falls back to a neutral clipboard glyph.
  final OrderType? type;
  final String? description;
  final String? status;
  final DateTime? dueDate;
  final String? technician;
  final VoidCallback? onTap;

  static const _icons = {
    OrderType.workOrder: LucideIcons.wrench,
    OrderType.preventive: LucideIcons.shieldCheck,
    OrderType.reactive: LucideIcons.zap,
    OrderType.annual: LucideIcons.calendarCheck,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = context.chips;
    final radius = BorderRadius.circular(context.radii.xl);

    final reference = referenceId.isNotEmpty
        ? referenceId
        : (id.length > 6 ? id.substring(0, 6) : id);
    final overdue = dueDate != null && isOverdueDate(dueDate!);
    final technicianLabel = (technician == null || technician!.trim().isEmpty)
        ? 'Unassigned'
        : technician!.trim();
    final priorityStyle = chips.priorityOnCard(priority);
    final typeColor = type == null
        ? AppColors.gray500
        : context.orderTypeColors.forType(type!);

    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: radius,
              boxShadow: FeElevation.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        type == null
                            ? LucideIcons.clipboardList
                            : _icons[type]!,
                        size: 18,
                        color: typeColor,
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
                                  '#$reference',
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.gray500,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              if (status != null && status!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                TechChipCompact(
                                  label: status!,
                                  style: chips.status(status),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 15,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.gray900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Text(
                      description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.gray500,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.gray100)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // The date never truncates: a due date reading
                            // "Sep 24…" tells a technician nothing. The
                            // technician name yields instead.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: overdue
                                    ? AppColors.red50
                                    : AppColors.gray50,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.calendar,
                                    size: 12,
                                    color: overdue
                                        ? AppColors.red500
                                        : AppColors.gray400,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dueDate == null ? '' : formatDate(dueDate!),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: overdue
                                          ? AppColors.red600
                                          : AppColors.gray600,
                                      fontWeight: overdue
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              height: 20,
                              width: 20,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: AppColors.orange100,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                technicianLabel[0].toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.orange700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                technicianLabel,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.gray600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: priorityStyle.background,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              priority,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: priorityStyle.foreground,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more,
                              size: 12,
                              color: priorityStyle.foreground.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// Status pill on a card: 10 px, uppercase, wide tracking.
class TechChipCompact extends StatelessWidget {
  const TechChipCompact({super.key, required this.label, required this.style});

  final String label;
  final FeChipStyle style;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: style.background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 10,
        color: style.foreground,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}
