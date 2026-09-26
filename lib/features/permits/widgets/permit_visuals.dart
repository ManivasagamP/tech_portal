import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../core/permit/permit_gas.dart';
import '../../../domain/permit.dart';
import '../../../theme/fe_colors.dart';
import '../../../theme/fe_permit_colors.dart';
import '../../../theme/fe_status_tokens.dart';
import '../../../theme/theme_extensions.dart';

/// Translates [key] and fills its `%a` slots — the same small helper
/// `snagTr` provides for Snag Assistant (features/snags/widgets/snag_visuals.dart),
/// kept local here so the permits module has no import-time dependency on it.
String permitTr(BuildContext context, String key, [List<Object> args = const []]) {
  final text = key.getString(context);
  return args.isEmpty ? text : context.formatString(text, args.map((a) => '$a').toList());
}

/// One place that turns the PTW vocabulary (type, status, risk, gas verdict)
/// into labels and colours, so the hub, the detail header and the sheets can
/// never disagree about what a status or a risk level looks like. Icon/badge
/// per type is [PermitVisuals] in `theme/fe_permit_colors.dart`; this layer
/// adds the i18n labels and the status/risk hues that need a `BuildContext`.
abstract final class PermitDisplay {
  static IconData typeIcon(String type) => PermitVisuals.icon(type);
  static FeBadgeStyle typeBadge(String type, FeAccents accents) => PermitVisuals.badge(type, accents);

  /// The catalogue's own label when it has one (real server copy), falling
  /// back to a local i18n key so the hub still reads sensibly the first time
  /// it ever runs, before the catalogue has been fetched.
  static String typeLabel(BuildContext context, PermitCatalog catalog, String type) {
    final fromCatalog = catalog.typeDef(type)?.label;
    if (fromCatalog != null && fromCatalog.isNotEmpty) return fromCatalog;
    return 'permits.type.$type'.getString(context);
  }

  static String statusLabel(BuildContext context, String status) =>
      'permits.status.$status'.getString(context);

  static Color statusHue(String status) => switch (status) {
    'active' => FeStatusHues.inProgress,
    'suspended' => FeStatusHues.priorityCritical,
    'approved' => FeStatusHues.open,
    'submitted' => FeStatusHues.onHold,
    'work_complete' => FeStatusHues.priorityMedium,
    'closed' => FeStatusHues.completed,
    'cancelled' => FeStatusHues.cancelled,
    'rejected' => FeStatusHues.priorityCritical,
    'expired' => FeStatusHues.overdue,
    _ => FeStatusHues.draft, // draft
  };

  static FeChipStyle statusChip(String status) => chip(statusHue(status));

  static Color riskHue(String level) => switch (level) {
    'critical' => FeStatusHues.priorityCritical,
    'high' => FeStatusHues.priorityHigh,
    'medium' => FeStatusHues.priorityMedium,
    _ => FeStatusHues.priorityLow, // low
  };

  static String riskLabel(BuildContext context, String level) => 'permits.risk.$level'.getString(context);

  static FeChipStyle chip(Color hue) => FeChipStyle(
    background: Color.alphaBlend(hue.withValues(alpha: 0.12), Colors.white),
    foreground: hue,
    border: hue.withValues(alpha: 0.28),
  );

  static Color gasVerdictColor(GasReadingVerdict v) => switch (v) {
    GasReadingVerdict.pass => FeColors.success,
    GasReadingVerdict.fail => FeColors.danger,
    GasReadingVerdict.unknown => FeColors.ink2,
  };

  /// The hero countdown's text and colour: amber under an hour left, red
  /// once past due — the spec's exact rule for the detail screen's big
  /// validity number.
  static (String, Color) countdown(BuildContext context, DateTime? validUntil, DateTime now) {
    if (validUntil == null) {
      return ('permits.validity_not_issued'.getString(context), FeColors.ink2);
    }
    final minutes = validUntil.difference(now).inMinutes;
    if (minutes < 0) {
      return (
        permitTr(context, 'permits.validity_expired_ago', [_duration(context, -minutes)]),
        FeColors.danger,
      );
    }
    final color = minutes < 60 ? FeColors.warning : FeColors.success;
    return (permitTr(context, 'permits.validity_remaining', [_duration(context, minutes)]), color);
  }

  static String _duration(BuildContext context, int minutes) {
    if (minutes < 60) return permitTr(context, 'permits.duration_minutes', [minutes]);
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins == 0
        ? permitTr(context, 'permits.duration_hours', [hours])
        : permitTr(context, 'permits.duration_hours_minutes', [hours, mins]);
  }
}
