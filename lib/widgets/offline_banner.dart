import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/offline/sync_client.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';

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
            ? 'Offline — your work is saved on this device'
                '${pending > 0 ? ' ($pending queued)' : ''}'
            : '$pending change${pending == 1 ? '' : 's'} waiting to sync';

        return Container(
          width: double.infinity,
          color: offline ? AppColors.slate800 : AppColors.amber50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                LucideIcons.cloudOff,
                size: 16,
                color: offline ? AppColors.white : AppColors.amber800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: offline ? AppColors.white : AppColors.amber800,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (!offline && pending > 0)
                TextButton(
                  onPressed: _syncing ? null : () => _syncNow(sync),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.amber900,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    backgroundColor: AppColors.amber200,
                  ),
                  child: Text(_syncing ? 'Syncing…' : 'Sync now'),
                ),
            ],
          ),
        );
      },
    );
  }
}
