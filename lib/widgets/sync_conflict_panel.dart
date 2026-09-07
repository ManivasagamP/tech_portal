import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/offline/offline_db.dart';
import '../state/providers.dart';
import '../core/utils/dates.dart';
import '../theme/fe_colors.dart';
import 'app_text.dart';
import 'common.dart';

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TechCard(
        tint: FeColors.dangerSoft,
        borderColor: FeColors.danger.withValues(alpha: 0.25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.triangleAlert, size: 16, color: FeColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText.bodyMedium(
                    'Some changes could not be saved',
                    color: FeColors.danger,
                    weight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await db.clearConflicts();
                    bus.notify();
                  },
                  style: TextButton.styleFrom(foregroundColor: FeColors.danger),
                  child: const AppText('Dismiss all'),
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
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({required this.conflict, required this.onDismiss});

  final SyncConflict conflict;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TechCard(
          padding: const EdgeInsets.all(12),
          radius: 12,
          borderColor: FeColors.danger.withValues(alpha: 0.25),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.bodyMedium(
                      conflict.label,
                      color: FeColors.ink,
                      weight: FontWeight.w600,
                    ),
                    const SizedBox(height: 2),
                    AppText.bodySmall(conflict.reason),
                    AppText.bodySmall(
                      formatDateTimeShort(conflict.at),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(LucideIcons.x, size: 16),
                color: FeColors.ink2,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      );
}
