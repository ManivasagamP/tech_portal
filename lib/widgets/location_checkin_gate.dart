import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/checkin_controller.dart';
import '../theme/fe_colors.dart';
import 'app_text.dart';
import 'common.dart';

/// Wraps the whole app (mounted in `app.dart`'s `MaterialApp.router` builder,
/// so it covers every route — shell tabs and full-screen pushes alike, unlike
/// a banner mounted only in `TechnicianShell`). While the technician's last
/// GPS fix is stale, [child] is inert (`AbsorbPointer`) and a blocking card
/// sits on top — the server already refuses every mutating request with 428
/// while stale (`middleware/auth.ts`), so letting the technician wander the
/// UI in that state just produces confusing failures; this stops them before
/// they start. Read-only browsing behind the scrim is still visible, but not
/// reachable, matching the deliberately non-dismissible
/// `_showSessionExpired` dialog in `technician_shell.dart`.
class LocationCheckInGate extends ConsumerWidget {
  const LocationCheckInGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkInControllerProvider);

    return Stack(
      children: [
        AbsorbPointer(absorbing: state.required, child: child),
        if (state.required) _Scrim(state: state),
      ],
    );
  }
}

class _Scrim extends ConsumerWidget {
  const _Scrim({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TechCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(LucideIcons.mapPin, size: 32, color: FeColors.warning),
                    const SizedBox(height: 12),
                    AppText.titleMedium(
                      'location_checkin.title'.getString(context),
                      align: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    AppText.bodySmall(
                      state.error ?? 'location_checkin.message'.getString(context),
                      color: state.error != null ? FeColors.danger : FeColors.ink2,
                      align: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: state.isChecking
                          ? null
                          : () => ref.read(checkInControllerProvider.notifier).checkIn(),
                      child: AppText(
                        state.isChecking
                            ? 'location_checkin.checking'.getString(context)
                            : 'location_checkin.share_button'.getString(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
