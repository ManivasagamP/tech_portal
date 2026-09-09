import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/offline/sync_client.dart';
import '../../core/utils/checklist_status.dart';
import '../../core/utils/dates.dart';
import '../../domain/maintenance_record.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/tech_popup.dart';

/// Work-order status block. Read-only: Start and Complete live on the
/// checklist tab, which has the completion context the close flow needs.
class TimeTrackerCard extends StatefulWidget {
  const TimeTrackerCard({
    super.key,
    required this.startedDate,
    required this.completedDate,
    required this.actualHours,
    required this.queuedComplete,
  });

  final DateTime? startedDate;
  final DateTime? completedDate;
  final double? actualHours;
  final bool queuedComplete;

  @override
  State<TimeTrackerCard> createState() => _TimeTrackerCardState();
}

class _TimeTrackerCardState extends State<TimeTrackerCard> {
  Duration _elapsed = Duration.zero;

  bool get _isCompleted =>
      widget.completedDate != null || widget.queuedComplete;
  bool get _isRunning => widget.startedDate != null && !_isCompleted;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    if (!mounted || !_isRunning) return;
    setState(() => _elapsed = DateTime.now().difference(widget.startedDate!));
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  @override
  void didUpdateWidget(TimeTrackerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedDate != widget.startedDate) _tick();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FeColors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
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
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.clock,
                  size: 16,
                  color: Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Time Tracking',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: FeColors.ink,
                  ),
                ),
              ),
              _StatusBadge(
                completed: widget.completedDate != null,
                queuedComplete: widget.queuedComplete,
                started: widget.startedDate != null,
              ),
            ],
          ),
          if (_isRunning) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Column(
                children: [
                  Text(
                    formatElapsed(_elapsed),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Time Elapsed',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
          if (widget.queuedComplete && widget.completedDate == null) ...[
            const SizedBox(height: 14),
            const _CompletedBanner(
              title: 'Completed — pending sync',
              subtitle: 'Hours will show once this syncs back online.',
            ),
          ],
          if (widget.completedDate != null && widget.actualHours != null) ...[
            const SizedBox(height: 14),
            _CompletedBanner(
              title: 'Total Hours',
              value: '${widget.actualHours} hrs',
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TrackingFact(
                  label: 'Started',
                  date: widget.startedDate,
                  fallback: 'Not started',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrackingFact(
                  label: 'Completed',
                  date: widget.completedDate,
                  fallback: widget.queuedComplete
                      ? 'Pending sync'
                      : 'Not completed',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackingFact extends StatelessWidget {
  const _TrackingFact({
    required this.label,
    required this.date,
    required this.fallback,
  });

  final String label;
  final DateTime? date;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                LucideIcons.calendar,
                size: 15,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                date == null
                    ? fallback
                    : '${formatDate(date!)}\n${formatTimeOfDay(date!)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FeColors.ink,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.completed,
    required this.queuedComplete,
    required this.started,
  });

  final bool completed;
  final bool queuedComplete;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = completed
        ? ('Completed', const Color(0xFFECFDF5), const Color(0xFF10B981))
        : queuedComplete
        ? (
            'Completed — pending sync',
            const Color(0xFFECFDF5),
            const Color(0xFF10B981),
          )
        : started
        ? ('In Progress', const Color(0xFFEFF6FF), const Color(0xFF0284C7))
        : ('Not Started', const Color(0xFFF1F5F9), const Color(0xFF64748B));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner({required this.title, this.subtitle, this.value});

  final String title;
  final String? subtitle;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (value != null) ...[
                const SizedBox(height: 2),
                Text(
                  value!,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.check,
              size: 20,
              color: Color(0xFF10B981),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status block for the three maintenance kinds, which have no timer card.
class ChecklistSummaryCard extends StatelessWidget {
  const ChecklistSummaryCard({super.key, required this.summary});

  final ChecklistSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FeColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(context.radii.card),
        border: Border.all(color: FeColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'CHECKLIST SUMMARY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: FeColors.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                AppText.headlineSmall(
                  summary.state.label,
                  color: FeColors.primary,
                  weight: FontWeight.w700,
                ),
                const SizedBox(height: 4),
                AppText.bodySmall(
                  '${summary.completedCount}/${summary.totalCount} actionable items complete',
                  color: FeColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: FeColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: AppText.caption(
              summary.state.label,
              color: Colors.white,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Accept/decline card. Renders nothing unless the invite is still pending.
/// Answers an invite. Returns a message worth showing the technician, or null
/// when the reply went through with nothing to say.
typedef InviteResponder = Future<String?> Function({
  required bool accept,
  String? reason,
});

class AssignmentInvitePanel extends ConsumerStatefulWidget {
  const AssignmentInvitePanel({
    super.key,
    required this.record,
    required this.respond,
  });

  final MaintenanceRecord record;

  /// Passed in rather than read from a provider: the detail screen answers
  /// through its own record controller, while the invite inbox answers through
  /// the list it has to refresh afterwards.
  final InviteResponder respond;

  @override
  ConsumerState<AssignmentInvitePanel> createState() =>
      _AssignmentInvitePanelState();
}

class _AssignmentInvitePanelState extends ConsumerState<AssignmentInvitePanel> {
  bool _responding = false;

  Future<void> _respond({required bool accept, String? reason}) async {
    setState(() => _responding = true);
    final message = await widget.respond(accept: accept, reason: reason);
    if (!mounted) return;
    setState(() => _responding = false);

    // `respond` returns null on a plain success, kOfflineQueuedMessage when
    // the reply is queued offline, or its own failure text — the only three
    // shapes it can hand back.
    final queued = message == kOfflineQueuedMessage;
    showTechPopup(
      context,
      message:
          message ??
          (accept
              ? 'This task is now yours.'
              : 'It has been passed to the next available technician.'),
      queued: queued,
      isError: message != null && !queued,
    );
  }

  Future<void> _openDeclineDialog() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _DeclineDialog(),
    );
    if (reason != null && reason.isNotEmpty) {
      await _respond(accept: false, reason: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.record.isAssignmentPending) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: TechCard(
        padding: const EdgeInsets.all(18),
        tint: FeColors.warningSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: FeColors.warning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.triangleAlert,
                    size: 18,
                    color: FeColors.warning,
                  ),
                ),
                const SizedBox(width: 10),
                AppText.titleSmall(
                  'Job Assignment Offer',
                  color: FeColors.warning,
                  weight: FontWeight.w700,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppText.bodySmall(
              'You have a pending job assignment for this task. Accept to claim the job, '
              'or decline with a reason to pass it back to dispatch.',
              color: FeColors.ink2,
            ),
            if (widget.record.assignmentChain.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AssignmentChain(chain: widget.record.assignmentChain),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _responding ? null : () => _respond(accept: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FeColors.success,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: const AppText('Accept'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _responding ? null : _openDeclineDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FeColors.danger,
                    side: BorderSide(
                      color: FeColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  icon: const Icon(LucideIcons.x, size: 16),
                  label: const AppText('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentChain extends StatelessWidget {
  const _AssignmentChain({required this.chain});

  final List<AssignmentChainEntry> chain;

  @override
  Widget build(BuildContext context) {
    final ordered = [...chain]
      ..sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));

    return Column(
      children: [
        for (final entry in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  switch (entry.status) {
                    'accepted' => LucideIcons.circleCheck,
                    'declined' => LucideIcons.circleX,
                    _ => LucideIcons.circleDashed,
                  },
                  size: 14,
                  color: switch (entry.status) {
                    'accepted' => FeColors.success,
                    'declined' => FeColors.danger,
                    _ => FeColors.warning,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText.bodySmall(
                    entry.technicianName,
                    color: FeColors.warning,
                  ),
                ),
                AppText.caption(entry.status, color: FeColors.warning),
              ],
            ),
          ),
      ],
    );
  }
}

class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog();

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: FeColors.panel,
    title: const AppText('Decline this assignment'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText.bodySmall(
          'Your reason is recorded on the task and shown to the admin. '
          'The task is then offered to the next available technician.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'e.g. Already on another site that day',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const AppText('Cancel'),
      ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: FeColors.danger,
          foregroundColor: Colors.white,
        ),
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
        child: const AppText('Confirm decline'),
      ),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText.caption(label, color: FeColors.ink2),
        const SizedBox(height: 2),
        AppText.bodyMedium(value, color: FeColors.ink, weight: FontWeight.w500),
      ],
    );
  }
}

/// Public alias so the detail screen can reuse the fact cell.
class DetailFact extends StatelessWidget {
  const DetailFact({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => _Fact(label: label, value: value);
}

class DetailMetaRow extends StatelessWidget {
  const DetailMetaRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 16, color: FeColors.ink2),
        const SizedBox(width: 8),
        Expanded(child: AppText.bodySmall(text, color: FeColors.ink2)),
      ],
    ),
  );
}
