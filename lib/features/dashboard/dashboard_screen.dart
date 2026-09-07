import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../state/auth_controller.dart';
import '../../state/dashboard_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/order_card.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/tech_header.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static String greetingFor(DateTime now) {
    if (now.hour < 12) return 'Good Morning';
    if (now.hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (!await showLogoutDialog(context)) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;
    final state = ref.watch(dashboardControllerProvider);
    final theme = Theme.of(context);
    final name = session?.name ?? 'Technician';

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: TechHeader(
        title: 'Technician Dashboard',
        onLogout: () => _logout(context, ref),
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(dashboardControllerProvider.notifier).refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // The hero card — the one summary that should read as the
            // headline of the page, not a peer of the cards below it.
            TechCard(
              dark: true,
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 52,
                    width: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.orange400, AppColors.orange600],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${greetingFor(DateTime.now())} \u{1F44B}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.gray400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ),
                        if (session?.email != null)
                          Text(
                            session!.email!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.gray400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: LucideIcons.qrCode,
                    label: 'Scan QR',
                    filled: true,
                    onTap: () => context.push(Routes.scan),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: LucideIcons.clipboardList,
                    label: 'Work Orders',
                    filled: false,
                    onTap: () => context.go(Routes.orders),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ProgressCard(
              completed: state.completedCount,
              total: state.totalCount,
              pending: !state.loaded,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _CounterCard(
                    label: 'Overdue',
                    caption: 'Pending',
                    icon: LucideIcons.circleAlert,
                    value: state.overdueCount,
                    pending: !state.loaded,
                    style: context.accents.rose,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CounterCard(
                    label: 'Due Today',
                    caption: 'Urgent',
                    icon: LucideIcons.clock,
                    value: state.dueTodayCount,
                    pending: !state.loaded,
                    style: context.accents.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "Today's Active Tasks",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: TechSpinner(),
              )
            else if (state.activeTasks.isEmpty)
              const TechEmptyState(
                icon: LucideIcons.circleAlert,
                title: 'No active tasks for today',
                subtitle: 'Great job!',
              )
            else
              for (var i = 0; i < state.activeTasks.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: StaggeredEntrance(
                    index: i,
                    child: Builder(
                      builder: (context) {
                        final record = state.activeTasks[i];
                        return OrderCard(
                          id: record.id,
                          type: record.type,
                          referenceId: record.referenceId ?? '',
                          title: record.focusTitle,
                          priority: record.displayPriority,
                          status: record.displayStatus,
                          dueDate: record.effectiveDate,
                          technician: record.technicianName,
                          onTap: () => context.push(
                            Routes.orderDetail(record.type.slug, record.id),
                          ),
                        );
                      },
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    final padding = const EdgeInsets.symmetric(vertical: 18);

    final button = filled
        ? ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(padding: padding),
            child: child,
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: padding,
              side: const BorderSide(color: AppColors.gray200, width: 1.5),
            ),
            child: child,
          );

    return PressableScale(scale: 0.96, child: button);
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.completed,
    required this.total,
    this.pending = false,
  });

  final int completed;
  final int total;

  /// Counts have never arrived yet. A dash says "not known"; a zero would be
  /// read as "nothing to do today", which is a different and wrong message.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total > 0 ? completed / total : 0.0;
    final percentage = fraction * 100;

    return TechCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProgressRing(
            value: pending ? null : fraction,
            size: 92,
            strokeWidth: 11,
            colors: const [
              AppColors.orange400,
              AppColors.orange600,
              AppColors.ink,
            ],
            child: Text(
              pending ? '—' : '${percentage.toStringAsFixed(0)}%',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.gray900,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'OVERALL PROGRESS',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.gray500,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      LucideIcons.trendingUp,
                      size: 16,
                      color: AppColors.orange600,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      pending ? '—' : '$completed',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: pending ? AppColors.gray300 : AppColors.gray900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pending ? 'Loading tasks' : '/ $total tasks',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.gray500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Completion rate',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.label,
    required this.caption,
    required this.icon,
    required this.value,
    required this.style,
    this.pending = false,
  });

  final String label;
  final String caption;
  final IconData icon;
  final int value;

  /// See [_ProgressCard.pending] — an unloaded overdue count of zero is a lie
  /// a technician would act on.
  final bool pending;
  final FeBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(context.radii.xl),
        boxShadow: FeElevation.tinted(style.foreground),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, style: style, size: 36, iconSize: 16),
          const SizedBox(height: 12),
          Text(
            pending ? '—' : '$value',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: pending ? AppColors.gray300 : AppColors.gray900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.gray500,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              caption.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: style.foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
