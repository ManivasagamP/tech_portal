import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/offline/prefetch.dart';
import '../../domain/technician_profile.dart';
import '../../state/auth_controller.dart';
import '../../state/profile_controller.dart';
import '../../state/providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/tech_header.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (!await showLogoutDialog(context)) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;
    final permissions = ref.watch(authControllerProvider).permissions;
    final page = ref.watch(technicianProfileProvider);

    final profile = page.valueOrNull?.profile;
    final metrics = page.valueOrNull?.metrics;
    final name = profile?.name.isNotEmpty == true
        ? profile!.name
        : (session?.name ?? 'Technician');

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: const TechHeader(title: 'Profile', showNotifications: false),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(technicianProfileProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _IdentityCard(
              name: name,
              email: profile?.email ?? session?.email,
              phone: profile?.phone,
              department: profile?.department ?? session?.department,
              status: profile?.status,
              experienceYears: profile?.experienceYears,
              specialization: profile?.specialization ?? const [],
            ),
            const SizedBox(height: 24),
            Text(
              'Performance',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (page.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: TechSpinner(),
              )
            else if (metrics == null)
              const TechEmptyState(
                icon: LucideIcons.chartNoAxesColumn,
                title: 'Figures are not available',
                subtitle: 'Pull down to try again.',
              )
            else
              _Metrics(metrics: metrics),
            if (profile != null && profile.certifications.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Certifications',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TechCard(
                child: Column(
                  children: [
                    for (final certification in profile.certifications)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            IconBadge(
                              icon: LucideIcons.award,
                              style: context.accents.amber,
                              size: 30,
                              iconSize: 15,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(certification)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            const _DownloadMyWork(),
            const SizedBox(height: 12),
            TechCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Fact(
                    label: 'Reference',
                    value: session?.technicianId ?? '—',
                  ),
                  _Fact(
                    label: 'Partner role',
                    value: session?.partnerRole ?? 'in-house',
                  ),
                  _Fact(
                    label: 'AI assistant',
                    value: permissions.isAiAgent ? 'Enabled' : 'Disabled',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: context.metrics.buttonDialog,
              child: OutlinedButton.icon(
                onPressed: () => _logout(context, ref),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.red50,
                  foregroundColor: AppColors.red600,
                  side: const BorderSide(color: AppColors.red200),
                ),
                icon: const Icon(LucideIcons.logOut, size: 18),
                label: const Text('Sign Out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.department,
    required this.status,
    required this.experienceYears,
    required this.specialization,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? department;
  final String? status;
  final double? experienceYears;
  final List<String> specialization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TechCard(
      dark: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 56,
                width: 56,
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
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                    if (email != null)
                      Text(
                        email!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                        ),
                      ),
                    if (phone != null)
                      Text(
                        phone!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.gray500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Fact(label: 'Department', value: department ?? 'N/A', dark: true),
          _Fact(label: 'Status', value: status ?? 'Active', dark: true),
          _Fact(
            label: 'Experience',
            value: '${_trimZero(experienceYears ?? 0)} years',
            dark: true,
          ),
          _Fact(
            label: 'Specialization',
            value: specialization.isEmpty ? 'N/A' : specialization.join(', '),
            dark: true,
          ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.metrics});

  final TechnicianMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        TechCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProgressRing(
                // The server has already worked this out as a percentage; it
                // is displayed, never recomputed.
                value: (metrics.completionRate / 100).clamp(0.0, 1.0),
                size: 84,
                strokeWidth: 10,
                colors: const [
                  AppColors.orange400,
                  AppColors.orange600,
                  AppColors.ink,
                ],
                child: Text(
                  '${_trimZero(metrics.completionRate)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
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
                          'Total orders',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.gray500,
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
                    const SizedBox(height: 6),
                    Text(
                      '${metrics.totalOrders}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppColors.gray900,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'complete',
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Completed',
                value: '${metrics.completedOrders}',
                caption: 'Successfully finished',
                accent: AppColors.green600,
                background: AppColors.green50,
                border: AppColors.green200,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: 'Avg. resolution',
                value: '${_trimZero(metrics.avgResolutionTime)} hrs',
                caption: 'Per order',
                accent: AppColors.purple600,
                background: AppColors.purple100,
                border: AppColors.purple100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Quality score',
                value: '${_trimZero(metrics.qualityScore)}/5',
                accent: AppColors.yellow700,
                background: AppColors.yellow100,
                border: AppColors.yellow200,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: 'Satisfaction',
                value: '${_trimZero(metrics.customerSatisfaction)}/5',
                accent: AppColors.orange600,
                background: AppColors.orange50,
                border: AppColors.orange200,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accent,
    required this.background,
    required this.border,
    this.caption,
  });

  final String label;
  final String value;
  final String? caption;
  final Color accent;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.xl),
        boxShadow: FeElevation.tinted(accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.gray600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.gray500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The dashboard warms the offline cache on its own, but a technician heading
/// somewhere with no signal wants to force it and be told it worked.
class _DownloadMyWork extends ConsumerStatefulWidget {
  const _DownloadMyWork();

  @override
  ConsumerState<_DownloadMyWork> createState() => _DownloadMyWorkState();
}

class _DownloadMyWorkState extends ConsumerState<_DownloadMyWork> {
  bool _busy = false;

  Future<void> _download() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.userId.isEmpty) return;

    setState(() => _busy = true);
    final result = await prefetchOfflineBundle(
      ref.read(syncClientProvider),
      session.userId,
      force: true,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    final message = result.offline
        ? 'No connection — nothing could be downloaded.'
        : result.failed > 0
        ? 'Saved ${result.saved} jobs. ${result.failed} could not be downloaded.'
        : 'Saved ${result.saved} jobs for offline use.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => TechCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconBadge(
              icon: LucideIcons.cloudDownload,
              style: context.accents.orange,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Download my work',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Save your jobs to this phone so they open in a plant room with '
          'no signal.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.gray600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _download,
            icon: _busy
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.download, size: 16),
            label: Text(_busy ? 'Downloading…' : 'Download my work'),
          ),
        ),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.dark = false});

  final String label;
  final String value;

  /// True inside the ink-dark identity card, where a light-mode fact row
  /// would otherwise render near-invisible grey-on-black.
  final bool dark;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.gray500, letterSpacing: 0.5),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: dark ? AppColors.white : AppColors.gray900,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// 2.0 reads as "2"; 2.5 stays "2.5". Whole numbers with a trailing zero look
/// like a rounding artefact next to a real score.
String _trimZero(num value) {
  final asDouble = value.toDouble();
  return asDouble == asDouble.roundToDouble()
      ? asDouble.round().toString()
      : asDouble.toStringAsFixed(1);
}
