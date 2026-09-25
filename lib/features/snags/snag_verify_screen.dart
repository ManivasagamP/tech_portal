import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/capture/capture_services.dart';
import '../../core/network/api_exception.dart';
import '../../core/snag/snag_rules.dart';
import '../../data/snag_repository.dart';
import '../../domain/snag.dart';
import '../../state/snag_controller.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/fe_header.dart';
import '../../widgets/tech_popup.dart';
import 'ghost_camera_screen.dart';
import 'widgets/snag_sheets.dart';
import 'widgets/snag_visuals.dart';

/// UC-7 — the verify run. Every snag someone *else* marked ready, one card
/// at a time: drag the compare slider, then accept or reject. The queue is a
/// snapshot taken on open, so acting on one card never reshuffles the rest
/// under the verifier's thumb.
class SnagVerifyScreen extends ConsumerStatefulWidget {
  const SnagVerifyScreen({super.key, required this.buildingId});
  final String buildingId;

  @override
  ConsumerState<SnagVerifyScreen> createState() => _SnagVerifyScreenState();
}

class _SnagVerifyScreenState extends ConsumerState<SnagVerifyScreen> {
  List<Snag>? _queue;
  var _index = 0;
  var _accepted = 0;
  var _rejected = 0;
  var _skipped = 0;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = ref.read(snagActorProvider)?.id ?? '';
    final snags = await ref.read(snagRepositoryProvider).local(buildingId: widget.buildingId);
    if (!mounted) return;
    setState(() => _queue = SnagQueues.toVerify(me, snags.where((s) => !s.localOnly)));
  }

  Future<bool> _act(Future<SnagWriteResult> Function(SnagRepository, SnagActor) op) async {
    final actor = ref.read(snagActorProvider);
    if (actor == null) return false;
    setState(() => _busy = true);
    try {
      final r = await op(ref.read(snagRepositoryProvider), actor);
      if (!mounted) return false;
      bumpSnags(ref);
      if (!r.synced) showTechPopup(context, message: 'snags.saved_on_device'.getString(context), queued: true);
      return true;
    } on SnagRuleException catch (e) {
      if (mounted) showTechPopup(context, message: e.failure.message, isError: true);
      return false;
    } on ApiFailure catch (e) {
      if (mounted) showTechPopup(context, message: e.message, isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(Snag s) async {
    if (await _act((repo, a) => repo.transition(s, SnagAction.verify, a))) {
      setState(() {
        _accepted++;
        _index++;
      });
    }
  }

  Future<void> _reject(Snag s) async {
    final reason = await showReasonSheet(context, title: 'snags.reject_title'.getString(context));
    if (reason == null || !mounted) return;
    if (await _act((repo, a) => repo.transition(s, SnagAction.reject, a, reason: reason))) {
      setState(() {
        _rejected++;
        _index++;
      });
    }
  }

  /// The verifier's own photo from the same angle, added as evidence before
  /// deciding — useful when the fixer's after photo is ambiguous.
  Future<void> _ownPhoto(Snag s) async {
    final photo = await Navigator.of(context).push<CapturedPhoto>(
      MaterialPageRoute(builder: (_) => GhostCameraScreen(before: s.coverPhoto, title: s.title)),
    );
    if (photo == null || !mounted) return;
    final ok = await _act((repo, a) => repo.addEvidence(s, a, photos: [photo], note: 'snags.verifier_photo'.getString(context)));
    if (ok && mounted) {
      final fresh = await ref.read(snagRepositoryProvider).localById(s.id);
      if (fresh != null && mounted) setState(() => _queue![_index] = fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    return Scaffold(
      backgroundColor: FeColors.page,
      appBar: FeHeader(title: 'snags.verify_run'.getString(context)),
      body: queue == null
          ? const TechSpinner()
          : queue.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: TechEmptyState(
                icon: LucideIcons.badgeCheck,
                iconColor: FeColors.success,
                title: 'snags.verify_empty'.getString(context),
                subtitle: 'snags.verify_empty_hint'.getString(context),
              ),
            )
          : _index >= queue.length
          ? _Summary(accepted: _accepted, rejected: _rejected, skipped: _skipped)
          : _card(queue, queue[_index]),
    );
  }

  Widget _card(List<Snag> queue, Snag s) {
    SnagActivity? readyEvent;
    for (final a in s.activity.reversed) {
      if (a.type == 'ready') {
        readyEvent = a;
        break;
      }
    }
    final after = s.afterPhotos;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / queue.length,
                    minHeight: 6,
                    backgroundColor: FeColors.line,
                    color: FeColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppText.caption('${_index + 1} / ${queue.length}', weight: FontWeight.w800),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => SlideTransition(
              position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: ListView(
              key: ValueKey(s.id),
              padding: const EdgeInsets.all(16),
              children: [
                CompareSlider(before: s.coverPhoto, after: after.isEmpty ? null : after.last, height: 340),
                const SizedBox(height: 14),
                Row(
                  children: [
                    TechChip(
                      label: SnagVisuals.priorityLabel(context, s.priority),
                      style: SnagVisuals.chip(SnagVisuals.priorityColor(s.priority)),
                    ),
                    const SizedBox(width: 6),
                    AppText.caption(s.displayRef, color: FeColors.ink2, weight: FontWeight.w700),
                    const Spacer(),
                    if (s.reopenedCount > 0)
                      TechChip(label: '↺${s.reopenedCount}', style: SnagVisuals.chip(FeColors.danger)),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => context.push(Routes.snagDetail(s.id)),
                  child: AppText.title(s.title),
                ),
                if (s.locationLabel != null) ...[
                  const SizedBox(height: 4),
                  AppText.bodySmall(s.locationLabel!),
                ],
                if (readyEvent != null) ...[
                  const SizedBox(height: 12),
                  TechCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.hammer, size: 16, color: FeColors.ink2),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText.bodySmall(
                                snagTr(context, 'snags.fixed_by', [readyEvent.byName ?? '—']),
                                weight: FontWeight.w700,
                              ),
                              if (readyEvent.note != null) AppText.bodySmall(readyEvent.note!),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _ownPhoto(s),
                    icon: const Icon(LucideIcons.ghost, size: 16),
                    label: Text('snags.take_own_photo'.getString(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'snags.skip'.getString(context),
                  onPressed: _busy ? null : () => setState(() {
                    _skipped++;
                    _index++;
                  }),
                  icon: const Icon(LucideIcons.skipForward, color: FeColors.ink2),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      foregroundColor: FeColors.danger,
                      side: const BorderSide(color: FeColors.danger, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _busy ? null : () => _reject(s),
                    icon: const Icon(LucideIcons.x),
                    label: Text('snags.action.reject'.getString(context), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: FeColors.success,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _busy ? null : () => _accept(s),
                    icon: const Icon(LucideIcons.check),
                    label: Text('snags.action.verify'.getString(context), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.accepted, required this.rejected, required this.skipped});
  final int accepted;
  final int rejected;
  final int skipped;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int n, Color c) => Expanded(
      child: TechCard(
        tint: c.withValues(alpha: 0.08),
        child: Column(
          children: [
            AppText.display('$n', color: c, weight: FontWeight.w800),
            AppText.bodySmall(label, align: TextAlign.center),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const IconBadge(
            icon: LucideIcons.partyPopper,
            style: FeBadgeStyle(background: FeColors.successSoft, foreground: FeColors.success),
            size: 72,
            iconSize: 32,
          ),
          const SizedBox(height: 12),
          AppText.title('snags.verify_done'.getString(context)),
          const SizedBox(height: 20),
          Row(
            children: [
              stat('snags.accepted'.getString(context), accepted, FeColors.success),
              const SizedBox(width: 10),
              stat('snags.rejected'.getString(context), rejected, FeColors.danger),
              const SizedBox(width: 10),
              stat('snags.skipped'.getString(context), skipped, FeColors.ink2),
            ],
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => context.pop(),
            child: Text('snags.done'.getString(context)),
          ),
        ],
      ),
    );
  }
}
