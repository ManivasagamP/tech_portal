import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../state/permit_controller.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/fe_header.dart';

/// The worksite-QR landing spot (`Routes.permitByToken`). The scanner hands
/// this screen a bare token; it calls `GET /by-token/:token` and, once the
/// permit resolves, replaces itself with the real detail screen — so a
/// technician backing out of the permit lands wherever the scan itself was
/// opened from (the scanner or a notification), never on this loading frame.
class PermitResolveScreen extends ConsumerWidget {
  const PermitResolveScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(permitByTokenProvider(token));

    return Scaffold(
      appBar: FeHeader(title: 'permits.title'.getString(context)),
      body: async.when(
        loading: () => const Center(child: TechSpinner()),
        error: (error, stack) => _NotFound(token: token),
        data: (permit) {
          if (permit == null) return _NotFound(token: token);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.pushReplacement(Routes.permitDetail(permit.id));
            }
          });
          return const Center(child: TechSpinner());
        },
      ),
    );
  }
}

class _NotFound extends ConsumerWidget {
  const _NotFound({required this.token});
  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TechEmptyState(
          icon: LucideIcons.qrCode,
          title: 'permits.scan_not_found'.getString(context),
          subtitle: 'permits.scan_not_found_sub'.getString(context),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(permitByTokenProvider(token)),
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: AppText('common.retry'.getString(context)),
        ),
      ],
    ),
  );
}
