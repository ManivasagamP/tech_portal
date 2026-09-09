import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/offline/sync_client.dart';
import '../state/providers.dart';
import '../theme/fe_colors.dart';
import 'app_text.dart';

/// Slate bar when offline, amber bar when online with a backlog. Renders nothing
/// when online and the queue is empty.
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key});

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  bool _syncing = false;

  Future<void> _syncNow(SyncClient sync) async {
    setState(() => _syncing = true);
    await sync.flushQueue();
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingMutationCountProvider).valueOrNull ?? 0;
    final sync = ref.watch(syncClientProvider);

    return FutureBuilder<bool>(
      future: sync.isOffline,
      builder: (context, snapshot) {
        final offline = snapshot.data ?? false;
        if (!offline && pending == 0) return const SizedBox.shrink();

        final text = offline
            ? (pending > 0
                ? context.formatString(
                    'widgets.offline_message_with_queued'.getString(context),
                    [pending],
                  )
                : 'widgets.offline_message'.getString(context))
            : context.formatString(
                (pending == 1
                        ? 'widgets.pending_sync_one'
                        : 'widgets.pending_sync_other')
                    .getString(context),
                [pending],
              );

        return Container(
          width: double.infinity,
          color: offline ? FeColors.ink : FeColors.warningSoft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                LucideIcons.cloudOff,
                size: 16,
                color: offline ? Colors.white : FeColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppText.bodySmall(
                  text,
                  color: offline ? Colors.white : FeColors.warning,
                  weight: FontWeight.w600,
                ),
              ),
              if (!offline && pending > 0)
                TextButton(
                  onPressed: _syncing ? null : () => _syncNow(sync),
                  style: TextButton.styleFrom(
                    foregroundColor: FeColors.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    backgroundColor: FeColors.warningSoft,
                  ),
                  child: AppText(
                    _syncing
                        ? 'widgets.syncing_label'.getString(context)
                        : 'widgets.sync_now'.getString(context),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
