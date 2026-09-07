import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/utils/dates.dart';
import '../../state/calendar_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import '../../widgets/order_card.dart';

/// A month at a glance, with the selected day's jobs underneath.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final month = ref.watch(calendarMonthProvider);
    final selected = ref.watch(calendarSelectedDayProvider);
    final records = ref.watch(calendarRecordsProvider);

    final buckets = bucketByDay(records.valueOrNull ?? const []);
    final days = monthGrid(month);
    final selectedRecords = buckets[formatDayKey(selected)] ?? const [];

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(title: const Text('Calendar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TechCard(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: ref
                          .read(calendarMonthProvider.notifier)
                          .previous,
                      icon: const Icon(LucideIcons.chevronLeft, size: 20),
                    ),
                    Expanded(
                      child: Text(
                        formatMonthTitle(month),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: ref.read(calendarMonthProvider.notifier).next,
                      icon: const Icon(LucideIcons.chevronRight, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final label in _weekdayLabels)
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.gray500,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (records.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: TechSpinner(),
                  )
                else
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final day in days)
                        _DayCell(
                          day: day,
                          inMonth: day.month == month.month,
                          selected: isSameDay(day, selected),
                          hasWork: (buckets[formatDayKey(day)] ?? const [])
                              .isNotEmpty,
                          onTap: () => ref
                              .read(calendarSelectedDayProvider.notifier)
                              .select(day),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            formatFullDay(selected),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (selectedRecords.isEmpty)
            const TechEmptyState(
              icon: LucideIcons.calendarDays,
              title: 'Nothing scheduled',
              subtitle: 'No work is due on this day.',
            )
          else
            for (final record in selectedRecords)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OrderCard(
                  id: record.id,
                  type: record.type,
                  referenceId: record.referenceId ?? '',
                  title: record.cardTitle,
                  description: record.description,
                  priority: record.displayPriority,
                  status: record.displayStatus,
                  dueDate: record.effectiveDate,
                  technician: record.technicianName,
                  onTap: () => context.push(
                    Routes.orderDetail(record.type.slug, record.id),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.hasWork,
    required this.onTap,
  });

  final DateTime day;

  /// Days from the neighbouring months pad the grid out; they stay tappable but
  /// are dimmed so the month still reads as a block.
  final bool inMonth;
  final bool selected;
  final bool hasWork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = isSameDay(day, DateTime.now());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.md),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? AppColors.orange600 : Colors.transparent,
          borderRadius: BorderRadius.circular(context.radii.md),
          border: today && !selected
              ? Border.all(color: AppColors.orange200)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected
                    ? AppColors.white
                    : inMonth
                    ? AppColors.gray900
                    : AppColors.gray300,
                fontWeight: today || selected ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              height: 4,
              width: 4,
              decoration: BoxDecoration(
                color: hasWork
                    ? (selected ? AppColors.white : AppColors.orange600)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
