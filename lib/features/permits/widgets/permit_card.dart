import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../domain/permit.dart';
import '../../../theme/fe_colors.dart';
import '../../../theme/theme_extensions.dart';
import '../../../widgets/app_text.dart';
import '../../../widgets/common.dart';
import 'permit_visuals.dart';

/// One row on the "My permits" hub — type badge, permit number + title,
/// location, status chip, validity countdown, and (when it applies) the
/// "needs your signature" reminder.
class PermitCard extends StatelessWidget {
  const PermitCard({
    super.key,
    required this.permit,
    required this.catalog,
    required this.needsSignature,
    required this.onTap,
  });

  final PermitSummary permit;
  final PermitCatalog catalog;

  /// True when this technician is on the crew and the permit is live — see
  /// `state/permit_controller.dart`'s doc comment on why this is an
  /// approximation rather than a precise per-technician flag (the list
  /// endpoint does not carry one).
  final bool needsSignature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = PermitDisplay.typeBadge(permit.type, context.accents);
    final statusChip = PermitDisplay.statusChip(permit.status);
    final (countdownText, countdownColor) =
        permit.isLive ? PermitDisplay.countdown(context, permit.validUntil, DateTime.now()) : (null, null);
    final location = [permit.buildingName, permit.floorName, permit.spaceName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' › ');

    return TechCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: PermitDisplay.typeIcon(permit.type), style: badge),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppText.bodySmall(permit.permitNo, color: FeColors.ink2, weight: FontWeight.w700),
                    const SizedBox(width: 8),
                    TechChip(label: PermitDisplay.statusLabel(context, permit.status), style: statusChip),
                  ],
                ),
                const SizedBox(height: 4),
                AppText.titleSmall(permit.title, weight: FontWeight.w700, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  AppText.bodySmall(location, color: FeColors.ink2, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                if (countdownText != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(LucideIcons.clock, size: 14, color: countdownColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: AppText.caption(countdownText, color: countdownColor, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
                if (needsSignature) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: FeColors.warningSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AppText.caption(
                      'permits.needs_signature'.getString(context),
                      color: FeColors.warning,
                      weight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
