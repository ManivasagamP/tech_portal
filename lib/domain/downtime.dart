import 'package:flutter/widgets.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../core/network/envelope.dart';

/// How badly the asset was affected while it was down. The wire values are the
/// server's enum exactly; only the labels are ours.
enum DowntimeImpact {
  fullOutage('full_outage', 'Full outage — asset completely down'),
  degraded('degraded', 'Degraded — asset partly working'),
  noImpact('no_impact', 'No impact');

  const DowntimeImpact(this.wire, this.label);

  final String wire;

  /// English fallback / non-UI identifier — see [displayLabel] for the
  /// translated string to actually render in the downtime picker.
  final String label;

  String displayLabel(BuildContext context) => switch (this) {
        DowntimeImpact.fullOutage =>
          'downtime.impact_full_outage'.getString(context),
        DowntimeImpact.degraded => 'downtime.impact_degraded'.getString(context),
        DowntimeImpact.noImpact => 'downtime.impact_no_impact'.getString(context),
      };
}

/// The root causes the server's `model/root-cause.ts` accepts. The list is
/// duplicated here because a picker needs literal options — but whether a root
/// cause is *required* is never decided here. That answer only ever comes from
/// the server's 422 `missing[]`.
const kRootCauseOptions = <String>[
  'wear',
  'misuse',
  'installation_defect',
  'design_defect',
  'missed_maintenance',
  'environmental',
  'power_quality',
  'unknown',
];

String humanizeRootCause(String value) => value
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Translated form of [humanizeRootCause] for the eight known
/// [kRootCauseOptions] values — those humanize fine in English but don't
/// mechanically translate, so each gets its own key. Anything outside that
/// fixed list (shouldn't happen; the picker only offers these) falls back to
/// the English humanization rather than showing a raw untranslated key.
String displayRootCause(BuildContext context, String value) {
  const keys = {
    'wear': 'downtime.root_cause_wear',
    'misuse': 'downtime.root_cause_misuse',
    'installation_defect': 'downtime.root_cause_installation_defect',
    'design_defect': 'downtime.root_cause_design_defect',
    'missed_maintenance': 'downtime.root_cause_missed_maintenance',
    'environmental': 'downtime.root_cause_environmental',
    'power_quality': 'downtime.root_cause_power_quality',
    'unknown': 'downtime.root_cause_unknown',
  };
  final key = keys[value];
  return key != null ? key.getString(context) : humanizeRootCause(value);
}

/// The priorities the server's `rcaCloseGuard` demands a root cause for.
/// Compared case-insensitively: reactive maintenance stores its priority
/// lowercase while the other three kinds capitalise it, and a strict match
/// would hide the root-cause block on every critical reactive ticket — leaving
/// the technician facing a 422 with no field on screen that could satisfy it.
bool rcaRequiredForPriority(String? priority) {
  final p = priority?.trim().toLowerCase();
  if (p == null || p.isEmpty) return false;
  return p == 'critical' || p == 'high';
}

/// One row of `GET /api/fm/assets/{assetId}/downtime`. Since the
/// `downtime_logs` table was retired these are derived windows, and `id` reads
/// `"<source>:<recordId>"` rather than a row key — `source` and `sourceId` are
/// what say which record a window belongs to.
class DowntimeWindow {
  const DowntimeWindow({
    required this.id,
    required this.source,
    required this.sourceId,
    required this.startedAt,
    this.reference,
    this.assetId,
    this.endedAt,
    this.derived = false,
  });

  final String id;

  /// `work-order` | `reactive` | `preventive` | `annual`.
  final String source;
  final String sourceId;
  final String? reference;
  final String? assetId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Inferred from lifecycle dates rather than explicitly recorded. A derived
  /// window is not somebody forgetting to press stop, so it is not treated as
  /// an open window.
  final bool derived;

  bool get isOpen => endedAt == null && !derived;

  static DowntimeWindow? fromJson(Map<String, dynamic> json) {
    final startedAt = asDate(json['startedAt']);
    if (startedAt == null) return null;
    return DowntimeWindow(
      id: json['id']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      sourceId: json['sourceId']?.toString() ?? '',
      reference: json['reference']?.toString(),
      assetId: json['assetId']?.toString(),
      startedAt: startedAt,
      endedAt: asDate(json['endedAt']),
      derived: asBool(json['derived']) ?? false,
    );
  }
}
