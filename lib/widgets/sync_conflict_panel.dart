import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/offline/offline_db.dart';
import '../state/providers.dart';
import '../core/utils/dates.dart';
import '../theme/app_colors.dart';

/// Mutations the server rejected while replaying. They are already dropped from
/// the queue — this is the only place the technician learns the work did not land.
class SyncConflictPanel extends ConsumerWidget {
  const SyncConflictPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(syncConflictsProvider).valueOrNull ?? const [];
    if (conflicts.isEmpty) return const SizedBox.shrink();

    final db = ref.watch(offlineDbProvider);
    final bus = ref.watch(queueBusProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.rose50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.rose200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.triangleAlert,
                  size: 16, color: AppColors.rose600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Some changes could not be saved',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.rose900,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await db.clearConflicts();
                  bus.notify();
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.rose600),
                child: const Text('Dismiss all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final conflict in conflicts)
            _ConflictRow(
              conflict: conflict,
              onDismiss: () async {
                await db.deleteConflict(conflict.id);
                bus.notify();
              },
            ),
        ],
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.conflict, required this.onDismiss});

  final SyncConflict conflict;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.rose200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conflict.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray900,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(conflict.reason,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    formatDateTimeShort(conflict.at),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(LucideIcons.x, size: 16),
              color: AppColors.gray400,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
}
