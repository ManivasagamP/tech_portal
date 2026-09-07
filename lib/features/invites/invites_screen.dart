import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../domain/maintenance_record.dart';
import '../../state/invites_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/tech_header.dart';
import '../order_detail/detail_widgets.dart';

/// Every invite the technician has not answered, in one place. The web built
/// this screen because the only other way to accept was to open the full task
/// page, which loads a checklist, a timer and a chat widget just to reach the
/// two buttons at the top.
class InvitesScreen extends ConsumerWidget {
  const InvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(invitesControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: const TechHeader(title: 'Assignments', showNotifications: false),
      body: RefreshIndicator(
        onRefresh: ref.read(invitesControllerProvider.notifier).refresh,
        child: invites.when(
          loading: () => const Center(child: TechSpinner()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              TechEmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Could not load your assignments',
                subtitle: 'Pull down to try again.',
              ),
            ],
          ),
          data: (records) => records.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    TechEmptyState(
                      icon: LucideIcons.clipboardCheck,
                      title: 'No pending assignments',
                      subtitle: 'New assignments will show up here.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length,
                  itemBuilder: (context, index) => StaggeredEntrance(
                    index: index,
                    child: _InviteTile(record: records[index]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.record});

  final MaintenanceRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.cardTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if ((record.referenceId ?? '').isNotEmpty)
                    record.referenceId!,
                  record.displayLocation,
                  record.displayPriority,
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.gray500,
                ),
              ),
            ],
          ),
        ),
        AssignmentInvitePanel(
          record: record,
          respond: ({required accept, reason}) async {
            final message = await ref
                .read(invitesControllerProvider.notifier)
                .respond(record, accept: accept, reason: reason);
            return message;
          },
        ),
        // Accepting is not the same as being ready to work: the task page is
        // still a tap away for anyone who wants to see what they just took on.
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: TextButton.icon(
            onPressed: () =>
                context.push(Routes.orderDetail(record.type.slug, record.id)),
            icon: const Icon(LucideIcons.arrowRight, size: 14),
            label: const Text('Open the task'),
          ),
        ),
      ],
    );
  }
}
