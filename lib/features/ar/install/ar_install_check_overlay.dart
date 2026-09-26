import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/ar/install_check.dart';
import '../../../core/ar/marker_code.dart';
import '../../../state/ar_install_controller.dart';
import '../../../state/ar_session_controller.dart';
import '../../../theme/fe_ar_colors.dart';
import '../../../theme/fe_colors.dart';
import '../../../widgets/app_text.dart';
import '../ar_ui.dart';
import '../widgets/ar_chrome.dart';
import '../widgets/ar_status.dart';
import '../widgets/ar_visuals.dart';

/// I3 Check, over the camera: the installer scans the board they just put
/// up and the phone checks it — right board, print scale, position against
/// the plan (or against a board already up), tilt — then takes the photo
/// and confirms. Nothing to measure; a celebration when it passes.
class ArInstallCheckOverlay extends ConsumerWidget {
  const ArInstallCheckOverlay({super.key, required this.tablet, required this.topInset});

  final bool tablet;
  final double topInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(arInstallProvider);
    final s = ref.watch(arSessionProvider);
    final code = st.expectedCode ?? '';
    final label = s.floor?.markerByCode(code)?.label ?? MarkerCode.display(code);
    final card = switch (st.phase) {
      ArInstallPhase.guide || ArInstallPhase.scanning => _ScanCard(label: label),
      ArInstallPhase.result || ArInstallPhase.saving || ArInstallPhase.done => _ResultCard(label: label),
    };
    final passed = st.phase == ArInstallPhase.done && ((st.result?.allGood ?? false) || st.keptAsBuilt);
    return Stack(
      children: [
        if (st.phase == ArInstallPhase.scanning) const Center(child: _Brackets()),
        PositionedDirectional(
          top: topInset + 8,
          start: 16,
          end: 16,
          child: Center(
            child: st.phase == ArInstallPhase.scanning
                ? ArGlassChip(text: arTr(context, 'ar.install.scan_chip', [label]), icon: ArIcons.board)
                : const ArSessionBadge(),
          ),
        ),
        if (tablet)
          PositionedDirectional(
            top: topInset + 64,
            start: 20,
            width: 380,
            bottom: 20,
            child: Align(alignment: AlignmentDirectional.topStart, child: SingleChildScrollView(child: card)),
          )
        else
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
              child: SingleChildScrollView(child: card),
            ),
          ),
        if (passed) const Positioned.fill(child: ArCelebration()),
      ],
    );
  }
}

class _Brackets extends StatelessWidget {
  const _Brackets();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 190, height: 230, child: ArLockRing(progress: 0, width: 190, height: 230));
}

class _ScanCard extends ConsumerWidget {
  const _ScanCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(arSessionProvider);
    final ctrl = ref.read(arInstallProvider.notifier);
    final activeNear = s.floor?.activeMarkers.where((m) => m.status == 'active').map((m) => m.label).take(2).toList() ?? const <String>[];
    return ArCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText.titleMedium(arTr(context, 'ar.install.scan_title', [label]), weight: FontWeight.w800),
          const SizedBox(height: 4),
          AppText.bodyMedium('ar.install.scan_body'.getString(context), color: FeColors.ink2),
          if (!s.isLocked && activeNear.isNotEmpty) ...[
            const SizedBox(height: 10),
            ArHintRow(text: arTr(context, 'ar.install.lock_first', [activeNear.join(' · ')])),
          ],
          if (s.demo) ...[
            const SizedBox(height: 10),
            _DemoRow(label: 'ar.demo.install_scan'.getString(context), onTap: () => ctrl.demoScan()),
            const SizedBox(height: 6),
            _DemoRow(label: 'ar.demo.install_swap'.getString(context), onTap: () => ctrl.demoScan(swap: true)),
          ],
          const SizedBox(height: 10),
          ArSecondaryButton(label: 'ar.install.back_to_guide'.getString(context), onPressed: () => context.pop()),
        ],
      ),
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(arInstallProvider);
    final s = ref.watch(arSessionProvider);
    final ctrl = ref.read(arInstallProvider.notifier);
    final r = st.result;
    if (r == null) return const SizedBox.shrink();
    final floorId = s.floor?.floorId;
    final run = floorId == null ? null : ref.watch(arInstallRunProvider(floorId)).valueOrNull;
    final next = run?.next;
    final done = st.phase == ArInstallPhase.done;
    final saving = st.phase == ArInstallPhase.saving;
    final seconds = st.checkedInMs == null ? null : (st.checkedInMs! / 1000).clamp(1, 99).round();

    String title;
    String? subtitle;
    var good = false;
    if (done && !(r.allGood || st.keptAsBuilt)) {
      title = 'ar.install.recorded'.getString(context);
      subtitle = 'ar.install.recorded_body'.getString(context);
    } else if (done) {
      good = true;
      title = arTr(context, 'ar.install.is_in', [label]);
      subtitle = r.firstOnFloor
          ? 'ar.install.first_note'.getString(context)
          : (seconds == null ? 'ar.install.nothing_to_measure'.getString(context) : arTr(context, 'ar.install.checked_in', [seconds]));
    } else if (!r.rightBoard) {
      title = arTr(context, 'ar.install.swap_title', [r.swappedWithLabel ?? '']);
      subtitle = 'ar.install.swap_body'.getString(context);
    } else if (r.scaleNeedsConfirm) {
      title = 'ar.install.scale_confirm_title'.getString(context);
      subtitle = 'ar.install.scale_confirm_body'.getString(context);
    } else if (!r.scaleOk) {
      title = arTr(context, 'ar.install.scale_title', [(r.scalePct ?? 0).round()]);
      subtitle = 'ar.install.scale_body'.getString(context);
    } else if (r.positionVerdict == InstallVerdict.keepAsBuilt) {
      title = arTr(context, 'ar.install.keep_title', [arCentimetres(context, r.positionM ?? 0)]);
      subtitle = 'ar.install.keep_body'.getString(context);
    } else if (r.positionVerdict == InstallVerdict.wrongSpot) {
      title = 'ar.install.wrong_title'.getString(context);
      subtitle = r.positionM == null ? null : arTr(context, 'ar.install.wrong_body', [arMetres(context, r.positionM!)]);
    } else if (!r.tiltOk) {
      title = 'ar.install.tilt_title'.getString(context);
      subtitle = arTr(context, 'ar.install.tilt_body', [(r.tiltDeg ?? 0).toStringAsFixed(1)]);
    } else {
      good = true;
      title = saving ? 'ar.install.saving'.getString(context) : arTr(context, 'ar.install.is_in', [label]);
    }

    final rows = <Widget>[
      _Row(
        ok: r.rightBoard,
        title: (r.rightBoard ? 'ar.installCheck.codeOk' : 'ar.installCheck.swap').getString(context),
        sub: r.rightBoard ? arTr(context, 'ar.install.code_sub', [label]) : null,
      ),
      if (r.rightBoard)
        _Row(
          ok: r.scaleOk,
          pending: r.scaleNeedsConfirm,
          title: (r.scaleNeedsConfirm
                  ? 'ar.installCheck.scaleConfirm'
                  : (r.scaleOk ? (r.scalePct == null ? 'ar.installCheck.scaleConfirmed' : 'ar.installCheck.scaleOk') : 'ar.installCheck.scaleOff'))
              .getString(context),
          sub: r.scalePct == null ? null : arTr(context, 'ar.install.scale_sub', [(r.scalePct! * 1.15).toStringAsFixed(1)]),
        ),
      if (r.rightBoard && r.scaleOk)
        _Row(
          ok: r.positionVerdict == InstallVerdict.ok || r.firstOnFloor,
          warn: r.positionVerdict == InstallVerdict.keepAsBuilt,
          title: r.firstOnFloor
              ? 'ar.installCheck.firstOnFloor'.getString(context)
              : (r.positionM == null
                    ? 'ar.installCheck.positionOk'.getString(context)
                    : arTr(context, 'ar.install.from_plan', [arCentimetres(context, r.positionM!)])),
          sub: r.pairLabel != null
              ? arTr(context, 'ar.install.checked_against', [r.pairLabel!])
              : (r.firstOnFloor ? null : 'ar.install.checked_against_lock'.getString(context)),
        ),
      if (r.rightBoard && r.scaleOk && r.tiltDeg != null)
        _Row(
          ok: r.tiltOk,
          title: (r.tiltOk ? 'ar.installCheck.level' : 'ar.installCheck.straighten').getString(context),
          sub: arTr(context, 'ar.install.tilt_sub', [r.tiltDeg!.toStringAsFixed(1)]),
        ),
      if (done)
        _Row(
          ok: true,
          title: (st.photoPath != null ? 'ar.install.photo_saved' : 'ar.install.saved').getString(context),
          sub: (st.queued ? 'ar.offline_saved' : 'ar.install.photo_sub').getString(context),
        ),
    ];

    final actions = <Widget>[];
    if (done) {
      if (run != null) {
        actions.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: run.total == 0 ? 0 : run.doneCount / run.total,
                      minHeight: 8,
                      color: FeColors.success,
                      backgroundColor: FeColors.line,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AppText.bodySmall(arTr(context, 'ar.install.progress', [run.doneCount, run.total, run.minutesLeft]), color: FeColors.ink2),
              ],
            ),
          ),
        );
      }
      if (next != null) {
        actions.add(ArPrimaryButton(
          label: arTr(context, 'ar.install.next_board', [next.marker.label]),
          icon: ArIcons.next,
          onPressed: () => context.pushReplacement(Routes.arInstallGuide(next.marker.code, floorId: floorId)),
        ));
      } else {
        actions.add(ArPrimaryButton(
          label: 'ar.install.all_done'.getString(context),
          icon: ArIcons.celebrate,
          color: FeColors.success,
          onPressed: () => context.pushReplacement(Routes.arInstall(floorId: floorId)),
        ));
      }
      actions.add(const SizedBox(height: 4));
      actions.add(TextButton(
        onPressed: () => context.pop(),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: AppText.label('ar.install.not_right'.getString(context), color: FeColors.primary, weight: FontWeight.w700),
      ));
    } else if (!r.rightBoard) {
      final swapped = s.floor?.markers.where((m) => m.label == r.swappedWithLabel).toList() ?? const [];
      if (swapped.isNotEmpty) {
        actions.add(ArPrimaryButton(
          label: arTr(context, 'ar.install.open_guide', [swapped.first.label]),
          onPressed: () => context.pushReplacement(Routes.arInstallGuide(swapped.first.code, floorId: floorId)),
        ));
        actions.add(const SizedBox(height: 8));
      }
      actions.add(ArSecondaryButton(label: 'ar.install.scan_again'.getString(context), onPressed: ctrl.startScan));
    } else if (r.scaleNeedsConfirm) {
      actions.add(ArPrimaryButton(label: 'ar.install.scale_yes'.getString(context), icon: ArIcons.check, onPressed: ctrl.confirmManualScale));
      actions.add(const SizedBox(height: 8));
      actions.add(ArSecondaryButton(label: 'ar.install.scan_again'.getString(context), onPressed: ctrl.startScan));
    } else if (!r.scaleOk) {
      actions.add(ArPrimaryButton(label: 'ar.install.record_reprint'.getString(context), busy: saving, onPressed: () => ctrl.confirm()));
      actions.add(const SizedBox(height: 8));
      actions.add(ArSecondaryButton(label: 'ar.install.scan_again'.getString(context), onPressed: ctrl.startScan));
    } else if (r.positionVerdict == InstallVerdict.keepAsBuilt) {
      actions.add(ArPrimaryButton(label: 'ar.install.keep'.getString(context), busy: saving, onPressed: ctrl.keepAsBuilt));
      actions.add(const SizedBox(height: 8));
      actions.add(ArSecondaryButton(label: 'ar.install.move'.getString(context), onPressed: ctrl.startScan));
    } else if (r.positionVerdict == InstallVerdict.wrongSpot) {
      actions.add(ArPrimaryButton(label: 'ar.install.show_spot'.getString(context), icon: ArIcons.plan, onPressed: () => context.pop()));
      actions.add(const SizedBox(height: 8));
      actions.add(ArSecondaryButton(label: 'ar.install.scan_again'.getString(context), onPressed: ctrl.startScan));
    } else if (!r.tiltOk) {
      actions.add(ArPrimaryButton(label: 'ar.install.scan_again'.getString(context), onPressed: ctrl.startScan));
    } else if (saving) {
      actions.add(const ArPrimaryButton(label: '', busy: true, onPressed: null));
    }
    if (st.errorKey != null) {
      actions.insert(0, Padding(padding: const EdgeInsets.only(bottom: 8), child: ArHintRow(text: st.errorKey!.getString(context), danger: true)));
    }

    return ArCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: good ? FeColors.success : FeColors.warning, shape: BoxShape.circle),
                  child: Icon(good ? ArIcons.check : ArIcons.warning, color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.title(title, weight: FontWeight.w800),
                    if (subtitle != null) AppText.bodySmall(subtitle, color: FeColors.ink2),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows,
          const SizedBox(height: 14),
          ...actions,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.ok, required this.title, this.sub, this.warn = false, this.pending = false});
  final bool ok;
  final bool warn;
  final bool pending;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = ok
        ? (FeArColors.lockedBg, FeArColors.lockedIcon, ArIcons.check)
        : (pending
              ? (FeArColors.manualBg, FeColors.ink2, ArIcons.help)
              : (warn ? (FeArColors.placedBg, FeColors.warning, ArIcons.warning) : (FeArColors.mismatchBg, FeColors.danger, ArIcons.close)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.bodyMedium(title, weight: FontWeight.w700),
                if (sub != null) AppText.bodySmall(sub!, color: FeColors.ink2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoRow extends StatelessWidget {
  const _DemoRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: FeArColors.placedFg,
        side: const BorderSide(color: FeColors.warning, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(ArIcons.demo, size: 16),
      label: AppText.label(label, color: FeArColors.placedFg, weight: FontWeight.w700),
    );
  }
}
