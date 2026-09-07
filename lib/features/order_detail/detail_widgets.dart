import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/utils/checklist_status.dart';
import '../../core/utils/dates.dart';
import '../../domain/maintenance_record.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';

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
    final theme = Theme.of(context);

    return TechCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.clock,
                size: 20,
                color: AppColors.orange600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Time Tracking',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.orange50,
                borderRadius: BorderRadius.circular(context.radii.lg),
              ),
              child: Column(
                children: [
                  Text(
                    formatElapsed(_elapsed),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: AppColors.orange600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Time Elapsed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.queuedComplete && widget.completedDate == null) ...[
            const SizedBox(height: 16),
            _CompletedBanner(
              title: 'Completed — pending sync',
              subtitle: 'Hours will show once this syncs back online.',
            ),
          ],
          if (widget.completedDate != null && widget.actualHours != null) ...[
            const SizedBox(height: 16),
            _CompletedBanner(
              title: 'Total Hours',
              value: '${widget.actualHours} hrs',
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.gray200),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Fact(
                  label: 'Started',
                  value: widget.startedDate == null
                      ? 'Not started'
                      : formatDateTimeShort(widget.startedDate!),
                ),
              ),
              Expanded(
                child: _Fact(
                  label: 'Completed',
                  value: widget.completedDate != null
                      ? formatDateTimeShort(widget.completedDate!)
                      : widget.queuedComplete
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
    final (label, color) = completed
        ? ('Completed', AppColors.green600)
        : queuedComplete
        ? ('Completed — pending sync', AppColors.green600)
        : started
        ? ('In Progress', AppColors.blue600)
        : ('Not Started', AppColors.gray500);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AppColors.white, fontWeight: FontWeight.w600),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green50,
        borderRadius: BorderRadius.circular(context.radii.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.gray600,
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.green600,
                    ),
                  ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.circleCheck,
            size: 40,
            color: AppColors.green600,
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
        color: AppColors.orange50,
        borderRadius: BorderRadius.circular(context.radii.card),
        border: Border.all(color: AppColors.orange100),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHECKLIST SUMMARY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.orange600,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.state.label,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.completedCount}/${summary.totalCount} actionable items complete',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.orange700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orange600,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              summary.state.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message ??
              (accept
                  ? 'This task is now yours.'
                  : 'It has been passed to the next available technician.'),
        ),
      ),
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
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.amber50,
        borderRadius: BorderRadius.circular(context.radii.xl),
        boxShadow: FeElevation.tinted(AppColors.amber600),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.amber100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.triangleAlert,
                  size: 18,
                  color: AppColors.amber900,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Assignment invitation',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.amber900,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You have been invited to this task. Accept it, or decline with a '
            'reason so it can be reassigned.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.amber800,
            ),
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
                  backgroundColor: AppColors.emerald600,
                  foregroundColor: AppColors.white,
                ),
                icon: const Icon(LucideIcons.check, size: 16),
                label: const Text('Accept'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _responding ? null : _openDeclineDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red700,
                  side: const BorderSide(color: AppColors.red200),
                ),
                icon: const Icon(LucideIcons.x, size: 16),
                label: const Text('Decline'),
              ),
            ],
          ),
        ],
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
                    'accepted' => AppColors.emerald600,
                    'declined' => AppColors.red600,
                    _ => AppColors.amber600,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.technicianName,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.amber900),
                  ),
                ),
                Text(
                  entry.status,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.amber800),
                ),
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
    backgroundColor: AppColors.white,
    title: const Text('Decline this assignment'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your reason is recorded on the task and shown to the admin. '
          'The task is then offered to the next available technician.',
          style: Theme.of(context).textTheme.bodySmall,
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
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red600,
          foregroundColor: AppColors.white,
        ),
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Confirm decline'),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: AppColors.gray500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: AppColors.gray900,
          ),
        ),
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
        Icon(icon, size: 16, color: AppColors.gray600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.gray600),
          ),
        ),
      ],
    ),
  );
}
