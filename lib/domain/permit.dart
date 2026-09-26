import '../core/network/envelope.dart';

/// Permit to Work (PTW) domain (docs/permit-to-work.md). Tolerant models over
/// the server contract in `fusion-eco-client/lib/apis/permits.ts` — the
/// source of truth for every shape here; change both together.
///
/// The server is the only place any PTW *rule* is enforced. This app never
/// decides whether a permit can be issued, closed, extended or approved —
/// it renders [PermitDetail.readiness] (computed server-side by the same
/// code that enforces it) and offers exactly the one action
/// [PermitReadiness.nextAction] names. The one exception is live gas
/// colouring, which is pure arithmetic over [GasProfile.limits] — see
/// `core/permit/permit_gas.dart`.
///
/// Enum-ish wire values (type, status, action, role, stage…) are kept as
/// plain `String`s rather than Dart enums, the same choice `domain/snag.dart`
/// makes: the vocabulary is server-owned and can grow (a new permit type, a
/// new blocker code) without a client rebuild. Helper getters like
/// [PermitStatusX.isLive] cover the few places behaviour depends on the
/// value.

// ---------------------------------------------------------------- vocabulary

const kPermitLiveStatuses = <String>{
  'submitted',
  'approved',
  'active',
  'suspended',
  'work_complete',
};
const kPermitTerminalStatuses = <String>{'closed', 'cancelled', 'rejected'};

extension PermitStatusX on String {
  /// Still open work in some form — awaiting approval through close-out.
  bool get isLivePermitStatus => kPermitLiveStatuses.contains(this);
  bool get isTerminalPermitStatus => kPermitTerminalStatuses.contains(this);
  bool get isActivePermitStatus => this == 'active';
  bool get isSuspendedPermitStatus => this == 'suspended';
}

// ---------------------------------------------------------------- shared bits

class PermitFlags {
  const PermitFlags({
    this.occupiedArea = false,
    this.outOfHours = false,
    this.outdoor = false,
    this.fireSystemImpairment = false,
    this.impairedZones = const [],
  });

  final bool occupiedArea;
  final bool outOfHours;

  /// Outdoor/exposed work — heat-stress check + midday-ban warning.
  final bool outdoor;
  final bool fireSystemImpairment;
  final List<String> impairedZones;

  factory PermitFlags.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return PermitFlags(
      occupiedArea: asBool(m['occupiedArea']) ?? false,
      outOfHours: asBool(m['outOfHours']) ?? false,
      outdoor: asBool(m['outdoor']) ?? false,
      fireSystemImpairment: asBool(m['fireSystemImpairment']) ?? false,
      impairedZones: m['impairedZones'] is List
          ? (m['impairedZones'] as List).map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// The approval stage currently waiting on a signature (submitted permits
/// only) — [PermitSummary.currentStage].
class PermitStage {
  const PermitStage({
    required this.stage,
    this.label,
    this.assigneeId,
    this.assigneeName,
  });

  final String stage;
  final String? label;
  final String? assigneeId;
  final String? assigneeName;

  static PermitStage? fromJson(dynamic json) {
    if (json is! Map) return null;
    final stage = json['stage']?.toString();
    if (stage == null || stage.isEmpty) return null;
    return PermitStage(
      stage: stage,
      label: firstNonEmpty([json['label']]),
      assigneeId: firstNonEmpty([json['assigneeId']]),
      assigneeName: firstNonEmpty([json['assigneeName']]),
    );
  }
}

/// One step of the request → approve → prepare → live → close strip.
class LifecycleStep {
  const LifecycleStep({
    required this.key,
    required this.label,
    required this.state,
  });

  /// request | approve | prepare | live | close
  final String key;
  final String label;

  /// done | current | blocked | todo | skipped
  final String state;

  bool get isDone => state == 'done';
  bool get isCurrent => state == 'current';
  bool get isBlocked => state == 'blocked';
  bool get isSkipped => state == 'skipped';

  factory LifecycleStep.fromJson(Map<String, dynamic> json) => LifecycleStep(
    key: json['key']?.toString() ?? '',
    label: firstNonEmpty([json['label']]) ?? '',
    state: json['state']?.toString() ?? 'todo',
  );
}

/// The one action the detail screen should offer right now. Every other
/// live action renders as "Waiting on the office: <label>" instead of a
/// button — see `permit_detail_screen.dart`.
class PermitNextAction {
  const PermitNextAction({
    required this.action,
    required this.label,
    required this.by,
    this.target,
  });

  /// A [PermitAction] wire value, or one of: record_gas_test,
  /// apply_isolations, sign_on_crew, tick_checks, acknowledge_conflicts,
  /// restore_isolations, sign_off_crew.
  final String action;
  final String label;

  /// requester | approver | issuer | crew | anyone
  final String by;
  final String? target;

  /// True when this device's technician is the one this action is asking
  /// for — a crew action, or one anyone can do (e.g. `suspend`).
  bool get isForCrew => by == 'crew' || by == 'anyone';

  static PermitNextAction? fromJson(dynamic json) {
    if (json is! Map) return null;
    final action = json['action']?.toString();
    if (action == null || action.isEmpty) return null;
    return PermitNextAction(
      action: action,
      label: firstNonEmpty([json['label']]) ?? action,
      by: json['by']?.toString() ?? 'anyone',
      target: firstNonEmpty([json['target']]),
    );
  }
}

class PermitBlocker {
  const PermitBlocker({
    required this.code,
    required this.message,
    required this.severity,
    required this.target,
  });

  final String code;
  final String message;

  /// block | warn
  final String severity;

  /// details | approvals | checks | closeChecks | isolations | gas | crew |
  /// conflicts | validity | fireWatch
  final String target;

  bool get isBlocking => severity == 'block';

  factory PermitBlocker.fromJson(Map<String, dynamic> json) => PermitBlocker(
    code: json['code']?.toString() ?? '',
    message: firstNonEmpty([json['message']]) ?? '',
    severity: json['severity']?.toString() ?? 'warn',
    target: json['target']?.toString() ?? 'details',
  );
}

class PermitActivity {
  const PermitActivity({
    required this.id,
    required this.at,
    required this.type,
    this.by,
    this.byName,
    this.note,
    this.reason,
  });

  final String id;
  final DateTime at;
  final String type;
  final String? by;
  final String? byName;
  final String? note;
  final String? reason;

  factory PermitActivity.fromJson(Map<String, dynamic> json) => PermitActivity(
    id: json['id']?.toString() ?? '',
    at: asDate(json['at']) ?? DateTime.now(),
    type: json['type']?.toString() ?? 'comment',
    by: firstNonEmpty([json['by']]),
    byName: firstNonEmpty([json['byName']]),
    note: firstNonEmpty([json['note']]),
    reason: firstNonEmpty([json['reason']]),
  );
}

class PermitAttachment {
  const PermitAttachment({
    required this.id,
    required this.url,
    required this.name,
    required this.kind,
    required this.at,
    this.by,
    this.byName,
  });

  final String id;
  final String url;
  final String name;

  /// photo | document | signature
  final String kind;
  final DateTime at;
  final String? by;
  final String? byName;

  factory PermitAttachment.fromJson(Map<String, dynamic> json) => PermitAttachment(
    id: json['id']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    name: firstNonEmpty([json['name']]) ?? 'Attachment',
    kind: json['kind']?.toString() ?? 'document',
    at: asDate(json['at']) ?? DateTime.now(),
    by: firstNonEmpty([json['by']]),
    byName: firstNonEmpty([json['byName']]),
  );
}

// ---------------------------------------------------------------- crew

class PermitCrew {
  const PermitCrew({
    required this.id,
    required this.permitId,
    required this.name,
    required this.role,
    this.technicianId,
    this.userId,
    this.company,
    this.phone,
    this.competencyMissing = const [],
    this.briefedAt,
    this.signedOnAt,
    this.signedOffAt,
    this.signatureUrl,
    this.status = 'expected',
  });

  final String id;
  final String permitId;
  final String name;

  /// supervisor | performer | fire_watch | attendant | entrant | rescue |
  /// banksman | spotter
  final String role;
  final String? technicianId;
  final String? userId;
  final String? company;
  final String? phone;
  final List<String> competencyMissing;
  final DateTime? briefedAt;
  final DateTime? signedOnAt;
  final DateTime? signedOffAt;
  final String? signatureUrl;

  /// expected | on_site | signed_off
  final String status;

  bool get isOnSite => status == 'on_site';
  bool get isSignedOff => status == 'signed_off';
  bool get needsSignOn => signedOnAt == null;

  /// True when [technicianId]/[userId] matches the signed-in technician —
  /// the row this device may act on (sign on / sign off).
  bool isMe(String? sessionUserId) =>
      sessionUserId != null &&
      sessionUserId.isNotEmpty &&
      (technicianId == sessionUserId || userId == sessionUserId);

  factory PermitCrew.fromJson(Map<String, dynamic> json) => PermitCrew(
    id: json['id']?.toString() ?? '',
    permitId: json['permitId']?.toString() ?? '',
    name: firstNonEmpty([json['name']]) ?? 'Crew member',
    role: json['role']?.toString() ?? 'performer',
    technicianId: firstNonEmpty([json['technicianId']]),
    userId: firstNonEmpty([json['userId']]),
    company: firstNonEmpty([json['company']]),
    phone: firstNonEmpty([json['phone']]),
    competencyMissing: json['competencyMissing'] is List
        ? (json['competencyMissing'] as List).map((e) => e.toString()).toList()
        : const [],
    briefedAt: asDate(json['briefedAt']),
    signedOnAt: asDate(json['signedOnAt']),
    signedOffAt: asDate(json['signedOffAt']),
    signatureUrl: firstNonEmpty([json['signatureUrl']]),
    status: json['status']?.toString() ?? 'expected',
  );
}

// ---------------------------------------------------------------- isolation

class PermitIsolation {
  const PermitIsolation({
    required this.id,
    required this.permitId,
    required this.pointTag,
    this.description,
    required this.energyType,
    required this.method,
    this.assetId,
    this.assetName,
    this.lockNo,
    this.tagNo,
    this.status = 'planned',
    this.isolatedAt,
    this.isolatedBy,
    this.isolatedByName,
    this.verifiedAt,
    this.verifiedBy,
    this.verifiedByName,
    this.tryOut = false,
    this.restoredAt,
    this.restoredBy,
    this.restoredByName,
    this.photoUrl,
    this.note,
    this.sharedWith = const [],
  });

  final String id;
  final String permitId;
  final String pointTag;
  final String? description;
  final String energyType;
  final String method;
  final String? assetId;
  final String? assetName;
  final String? lockNo;
  final String? tagNo;

  /// planned | isolated | verified | restored
  final String status;
  final DateTime? isolatedAt;
  final String? isolatedBy;
  final String? isolatedByName;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final String? verifiedByName;
  final bool tryOut;
  final DateTime? restoredAt;
  final String? restoredBy;
  final String? restoredByName;
  final String? photoUrl;
  final String? note;

  /// Permit numbers of OTHER live permits listing this same point tag.
  final List<String> sharedWith;

  bool get isPlanned => status == 'planned';
  bool get isIsolated => status == 'isolated';
  bool get isVerified => status == 'verified';
  bool get isRestored => status == 'restored';

  /// Only the person who applied the lock may remove it (LOTO rule the
  /// server enforces on `/restore`; mirrored here only to grey the button,
  /// never to allow something the server would refuse).
  bool canRestore(String? sessionUserId) =>
      isVerified &&
      sessionUserId != null &&
      sessionUserId.isNotEmpty &&
      isolatedBy == sessionUserId;

  factory PermitIsolation.fromJson(Map<String, dynamic> json) => PermitIsolation(
    id: json['id']?.toString() ?? '',
    permitId: json['permitId']?.toString() ?? '',
    pointTag: firstNonEmpty([json['pointTag']]) ?? '',
    description: firstNonEmpty([json['description']]),
    energyType: json['energyType']?.toString() ?? '',
    method: json['method']?.toString() ?? '',
    assetId: firstNonEmpty([json['assetId']]),
    assetName: firstNonEmpty([json['assetName']]),
    lockNo: firstNonEmpty([json['lockNo']]),
    tagNo: firstNonEmpty([json['tagNo']]),
    status: json['status']?.toString() ?? 'planned',
    isolatedAt: asDate(json['isolatedAt']),
    isolatedBy: firstNonEmpty([json['isolatedBy']]),
    isolatedByName: firstNonEmpty([json['isolatedByName']]),
    verifiedAt: asDate(json['verifiedAt']),
    verifiedBy: firstNonEmpty([json['verifiedBy']]),
    verifiedByName: firstNonEmpty([json['verifiedByName']]),
    tryOut: asBool(json['tryOut']) ?? false,
    restoredAt: asDate(json['restoredAt']),
    restoredBy: firstNonEmpty([json['restoredBy']]),
    restoredByName: firstNonEmpty([json['restoredByName']]),
    photoUrl: firstNonEmpty([json['photoUrl']]),
    note: firstNonEmpty([json['note']]),
    sharedWith: json['sharedWith'] is List
        ? (json['sharedWith'] as List).map((e) => e.toString()).toList()
        : const [],
  );
}

// ---------------------------------------------------------------- gas

/// A gas the profile judges, and the inclusive band a reading must fall in.
/// Either bound may be absent (O2 has both; LEL/H2S/CO usually only `max`).
class GasLimit {
  const GasLimit({
    required this.gas,
    required this.label,
    required this.unit,
    this.min,
    this.max,
  });

  /// o2 | lel | h2s | co
  final String gas;
  final String label;

  /// "% vol" | "% LEL" | "ppm"
  final String unit;
  final double? min;
  final double? max;

  factory GasLimit.fromJson(Map<String, dynamic> json) => GasLimit(
    gas: json['gas']?.toString() ?? '',
    label: firstNonEmpty([json['label']]) ?? (json['gas']?.toString() ?? '').toUpperCase(),
    unit: firstNonEmpty([json['unit']]) ?? '',
    min: asDouble(json['min']),
    max: asDouble(json['max']),
  );
}

class GasProfile {
  const GasProfile({this.limits = const [], this.retestMinutes = 0});

  final List<GasLimit> limits;
  final int retestMinutes;

  GasLimit? limitFor(String gas) {
    for (final l in limits) {
      if (l.gas == gas) return l;
    }
    return null;
  }

  static const empty = GasProfile();

  factory GasProfile.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return GasProfile(
      limits: m['limits'] is List
          ? (m['limits'] as List)
                .whereType<Map>()
                .map((e) => GasLimit.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      retestMinutes: asInt(m['retestMinutes']) ?? 0,
    );
  }
}

class PermitGasFailure {
  const PermitGasFailure({required this.gas, this.value, required this.message});
  final String gas;
  final double? value;
  final String message;

  factory PermitGasFailure.fromJson(Map<String, dynamic> json) => PermitGasFailure(
    gas: json['gas']?.toString() ?? '',
    value: asDouble(json['value']),
    message: firstNonEmpty([json['message']]) ?? '',
  );
}

class PermitGasTest {
  const PermitGasTest({
    required this.id,
    required this.permitId,
    required this.testedAt,
    this.testedBy,
    this.testedByName,
    this.o2,
    this.lel,
    this.h2s,
    this.co,
    this.instrumentId,
    this.calibrationDue,
    this.location,
    this.result = 'pass',
    this.failures = const [],
    this.note,
  });

  final String id;
  final String permitId;
  final DateTime testedAt;
  final String? testedBy;
  final String? testedByName;
  final double? o2;
  final double? lel;
  final double? h2s;
  final double? co;
  final String? instrumentId;
  final DateTime? calibrationDue;
  final String? location;

  /// pass | fail
  final String result;
  final List<PermitGasFailure> failures;
  final String? note;

  bool get passed => result == 'pass';

  double? valueFor(String gas) => switch (gas) {
    'o2' => o2,
    'lel' => lel,
    'h2s' => h2s,
    'co' => co,
    _ => null,
  };

  factory PermitGasTest.fromJson(Map<String, dynamic> json) => PermitGasTest(
    id: json['id']?.toString() ?? '',
    permitId: json['permitId']?.toString() ?? '',
    testedAt: asDate(json['testedAt']) ?? DateTime.now(),
    testedBy: firstNonEmpty([json['testedBy']]),
    testedByName: firstNonEmpty([json['testedByName']]),
    o2: asDouble(json['o2']),
    lel: asDouble(json['lel']),
    h2s: asDouble(json['h2s']),
    co: asDouble(json['co']),
    instrumentId: firstNonEmpty([json['instrumentId']]),
    calibrationDue: asDate(json['calibrationDue']),
    location: firstNonEmpty([json['location']]),
    result: json['result']?.toString() == 'fail' ? 'fail' : 'pass',
    failures: json['failures'] is List
        ? (json['failures'] as List)
              .whereType<Map>()
              .map((e) => PermitGasFailure.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : const [],
    note: firstNonEmpty([json['note']]),
  );
}

// ---------------------------------------------------------------- approvals & checks

class PermitApproval {
  const PermitApproval({
    required this.stage,
    required this.label,
    required this.status,
    this.assigneeId,
    this.assigneeName,
    this.by,
    this.byName,
    this.at,
    this.comment,
  });

  /// area | hse | issuer
  final String stage;
  final String label;

  /// pending | approved | returned | rejected
  final String status;
  final String? assigneeId;
  final String? assigneeName;
  final String? by;
  final String? byName;
  final DateTime? at;
  final String? comment;

  factory PermitApproval.fromJson(Map<String, dynamic> json) => PermitApproval(
    stage: json['stage']?.toString() ?? '',
    label: firstNonEmpty([json['label']]) ?? '',
    status: json['status']?.toString() ?? 'pending',
    assigneeId: firstNonEmpty([json['assigneeId']]),
    assigneeName: firstNonEmpty([json['assigneeName']]),
    by: firstNonEmpty([json['by']]),
    byName: firstNonEmpty([json['byName']]),
    at: asDate(json['at']),
    comment: firstNonEmpty([json['comment']]),
  );
}

class PermitCheckState {
  const PermitCheckState({
    this.done = false,
    this.by,
    this.byName,
    this.at,
    this.note,
  });

  final bool done;
  final String? by;
  final String? byName;
  final DateTime? at;
  final String? note;

  factory PermitCheckState.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    return PermitCheckState(
      done: asBool(m['done']) ?? false,
      by: firstNonEmpty([m['by']]),
      byName: firstNonEmpty([m['byName']]),
      at: asDate(m['at']),
      note: firstNonEmpty([m['note']]),
    );
  }

  static Map<String, PermitCheckState> mapFromJson(dynamic json) {
    if (json is! Map) return const {};
    return {for (final e in json.entries) e.key.toString(): PermitCheckState.fromJson(e.value)};
  }
}

class PermitCheckDef {
  const PermitCheckDef({required this.id, required this.text, this.critical = false});

  final String id;
  final String text;
  final bool critical;

  factory PermitCheckDef.fromJson(Map<String, dynamic> json) => PermitCheckDef(
    id: json['id']?.toString() ?? '',
    text: firstNonEmpty([json['text']]) ?? '',
    critical: asBool(json['critical']) ?? false,
  );

  static List<PermitCheckDef> listFromJson(dynamic json) => json is List
      ? json.whereType<Map>().map((e) => PermitCheckDef.fromJson(Map<String, dynamic>.from(e))).toList()
      : const [];
}

/// The fire watch a permit type (e.g. hot work) requires once work starts —
/// [PermitDetail.fireWatch], distinct from the lighter `running`/
/// `minutesLeft` summary carried on [PermitReadiness].
class PermitFireWatch {
  const PermitFireWatch({
    required this.minutes,
    required this.startedAt,
    required this.endsAt,
    this.completedAt,
    this.by,
    this.byName,
    this.note,
  });

  final int minutes;
  final DateTime startedAt;
  final DateTime endsAt;
  final DateTime? completedAt;
  final String? by;
  final String? byName;
  final String? note;

  bool get isDone => completedAt != null;

  /// Never negative; zero once the countdown has elapsed.
  Duration remaining(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isElapsed(DateTime now) => !isDone && !endsAt.isAfter(now);

  static PermitFireWatch? fromJson(dynamic json) {
    if (json is! Map) return null;
    final startedAt = asDate(json['startedAt']);
    final endsAt = asDate(json['endsAt']);
    if (startedAt == null || endsAt == null) return null;
    return PermitFireWatch(
      minutes: asInt(json['minutes']) ?? 0,
      startedAt: startedAt,
      endsAt: endsAt,
      completedAt: asDate(json['completedAt']),
      by: firstNonEmpty([json['by']]),
      byName: firstNonEmpty([json['byName']]),
      note: firstNonEmpty([json['note']]),
    );
  }
}

class PermitEffective {
  const PermitEffective({
    this.types = const [],
    this.requiresIsolation = false,
    this.fireWatchMinutes = 0,
    this.requiredRoles = const [],
    this.maxHours = 0,
    this.maxExtensions = 0,
    this.gasRequired = false,
  });

  final List<String> types;
  final bool requiresIsolation;
  final int fireWatchMinutes;
  final List<String> requiredRoles;
  final int maxHours;
  final int maxExtensions;
  final bool gasRequired;

  static const empty = PermitEffective();

  factory PermitEffective.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    List<String> strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
    return PermitEffective(
      types: strings(m['types']),
      requiresIsolation: asBool(m['requiresIsolation']) ?? false,
      fireWatchMinutes: asInt(m['fireWatchMinutes']) ?? 0,
      requiredRoles: strings(m['requiredRoles']),
      maxHours: asInt(m['maxHours']) ?? 0,
      maxExtensions: asInt(m['maxExtensions']) ?? 0,
      gasRequired: asBool(m['gasRequired']) ?? false,
    );
  }
}

// ---------------------------------------------------------------- readiness

/// What the app actually renders: the server's own verdict on what can
/// happen next, computed by the same code that enforces it. Nothing here is
/// re-derived from the permit's other fields — every value is read straight
/// off the wire.
class PermitReadiness {
  const PermitReadiness({
    this.lifecycle = const [],
    this.nextAction,
    this.issueBlockers = const [],
    this.closeBlockers = const [],
    this.gasRequired = false,
    this.gasLastTestAt,
    this.gasLastResult,
    this.gasRetestMinutes,
    this.gasRetestDueAt,
    this.gasFresh = false,
    this.isolationRequired = false,
    this.isolationTotal = 0,
    this.isolationPlanned = 0,
    this.isolationIsolated = 0,
    this.isolationVerified = 0,
    this.isolationRestored = 0,
    this.crewTotal = 0,
    this.crewOnSite = 0,
    this.crewSignedOff = 0,
    this.crewMissingRoles = const [],
    this.checksPreDone = 0,
    this.checksPreTotal = 0,
    this.checksCloseDone = 0,
    this.checksCloseTotal = 0,
    this.validUntil,
    this.validityMinutesLeft,
    this.fireWatchRunning = false,
    this.fireWatchMinutesLeft,
    this.riskScore = 0,
    this.riskLevel = 'low',
    this.conflictCount = 0,
  });

  final List<LifecycleStep> lifecycle;
  final PermitNextAction? nextAction;
  final List<PermitBlocker> issueBlockers;
  final List<PermitBlocker> closeBlockers;

  final bool gasRequired;
  final DateTime? gasLastTestAt;

  /// pass | fail | null (never tested)
  final String? gasLastResult;
  final int? gasRetestMinutes;
  final DateTime? gasRetestDueAt;
  final bool gasFresh;

  final bool isolationRequired;
  final int isolationTotal;
  final int isolationPlanned;
  final int isolationIsolated;
  final int isolationVerified;
  final int isolationRestored;

  final int crewTotal;
  final int crewOnSite;
  final int crewSignedOff;
  final List<String> crewMissingRoles;

  final int checksPreDone;
  final int checksPreTotal;
  final int checksCloseDone;
  final int checksCloseTotal;

  final DateTime? validUntil;
  final int? validityMinutesLeft;

  final bool fireWatchRunning;
  final int? fireWatchMinutesLeft;

  final num riskScore;

  /// low | medium | high | critical
  final String riskLevel;

  final int conflictCount;

  /// All blockers currently in force — the "Blockers" section shows these,
  /// regardless of whether they gate issuing or closing.
  List<PermitBlocker> get allBlockers => [...issueBlockers, ...closeBlockers];
  bool get hasBlockingIssue => issueBlockers.any((b) => b.isBlocking);

  static const empty = PermitReadiness();

  factory PermitReadiness.fromJson(dynamic json) {
    final m = json is Map ? json : const {};
    final gas = m['gas'] is Map ? m['gas'] as Map : const {};
    final iso = m['isolation'] is Map ? m['isolation'] as Map : const {};
    final crew = m['crew'] is Map ? m['crew'] as Map : const {};
    final checks = m['checks'] is Map ? m['checks'] as Map : const {};
    final validity = m['validity'] is Map ? m['validity'] as Map : const {};
    final fw = m['fireWatch'] is Map ? m['fireWatch'] as Map : null;
    final risk = m['risk'] is Map ? m['risk'] as Map : const {};
    final conflicts = m['conflicts'] is List ? m['conflicts'] as List : const [];

    List<PermitBlocker> blockers(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => PermitBlocker.fromJson(Map<String, dynamic>.from(e))).toList()
        : const [];

    return PermitReadiness(
      lifecycle: m['lifecycle'] is List
          ? (m['lifecycle'] as List)
                .whereType<Map>()
                .map((e) => LifecycleStep.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      nextAction: PermitNextAction.fromJson(m['nextAction']),
      issueBlockers: blockers(m['issueBlockers']),
      closeBlockers: blockers(m['closeBlockers']),
      gasRequired: asBool(gas['required']) ?? false,
      gasLastTestAt: asDate(gas['lastTestAt']),
      gasLastResult: firstNonEmpty([gas['lastResult']]),
      gasRetestMinutes: asInt(gas['retestMinutes']),
      gasRetestDueAt: asDate(gas['retestDueAt']),
      gasFresh: asBool(gas['fresh']) ?? false,
      isolationRequired: asBool(iso['required']) ?? false,
      isolationTotal: asInt(iso['total']) ?? 0,
      isolationPlanned: asInt(iso['planned']) ?? 0,
      isolationIsolated: asInt(iso['isolated']) ?? 0,
      isolationVerified: asInt(iso['verified']) ?? 0,
      isolationRestored: asInt(iso['restored']) ?? 0,
      crewTotal: asInt(crew['total']) ?? 0,
      crewOnSite: asInt(crew['onSite']) ?? 0,
      crewSignedOff: asInt(crew['signedOff']) ?? 0,
      crewMissingRoles: crew['missingRoles'] is List
          ? (crew['missingRoles'] as List).map((e) => e.toString()).toList()
          : const [],
      checksPreDone: asInt(checks['preDone']) ?? 0,
      checksPreTotal: asInt(checks['preTotal']) ?? 0,
      checksCloseDone: asInt(checks['closeDone']) ?? 0,
      checksCloseTotal: asInt(checks['closeTotal']) ?? 0,
      validUntil: asDate(validity['validUntil']),
      validityMinutesLeft: asInt(validity['minutesLeft']),
      fireWatchRunning: fw != null ? (asBool(fw['running']) ?? false) : false,
      fireWatchMinutesLeft: fw != null ? asInt(fw['minutesLeft']) : null,
      riskScore: asDouble(risk['score']) ?? 0,
      riskLevel: firstNonEmpty([risk['level']]) ?? 'low',
      conflictCount: conflicts.length,
    );
  }
}

// ---------------------------------------------------------------- permit

/// A row in the "My permits" list.
class PermitSummary {
  const PermitSummary({
    required this.id,
    required this.permitNo,
    required this.type,
    this.secondaryTypes = const [],
    required this.status,
    required this.title,
    this.buildingId,
    this.buildingName,
    this.floorId,
    this.floorName,
    this.zoneId,
    this.zoneName,
    this.spaceId,
    this.spaceName,
    this.locationNote,
    this.assetId,
    this.assetName,
    this.workOrderId,
    this.workOrderRef,
    this.requestedBy,
    this.requestedByName,
    this.contractorCompany,
    this.supervisorName,
    this.plannedStart,
    this.plannedEnd,
    this.issuedAt,
    this.validUntil,
    this.completedAt,
    this.closedAt,
    this.riskScore = 0,
    this.riskLevel = 'low',
    this.currentStage,
    this.crewOnSite = 0,
    this.isolationsLive = 0,
    this.gasLastResult,
    this.fireWatchEndsAt,
    this.flags = const PermitFlags(),
    this.conflictCount = 0,
    this.maxConflictSeverity,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String permitNo;
  final String type;
  final List<String> secondaryTypes;
  final String status;
  final String title;
  final String? buildingId;
  final String? buildingName;
  final String? floorId;
  final String? floorName;
  final String? zoneId;
  final String? zoneName;
  final String? spaceId;
  final String? spaceName;
  final String? locationNote;
  final String? assetId;
  final String? assetName;
  final String? workOrderId;
  final String? workOrderRef;
  final String? requestedBy;
  final String? requestedByName;
  final String? contractorCompany;
  final String? supervisorName;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? issuedAt;
  final DateTime? validUntil;
  final DateTime? completedAt;
  final DateTime? closedAt;
  final num riskScore;
  final String riskLevel;
  final PermitStage? currentStage;
  final int crewOnSite;
  final int isolationsLive;
  final String? gasLastResult;
  final DateTime? fireWatchEndsAt;
  final PermitFlags flags;
  final int conflictCount;
  final String? maxConflictSeverity;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLive => status.isLivePermitStatus;
  bool get isActive => status.isActivePermitStatus;
  bool get isSuspended => status.isSuspendedPermitStatus;
  bool get fireWatchRunning => fireWatchEndsAt != null;

  /// Minutes left on [validUntil], negative once it has expired. Null when
  /// there is no validity window yet (not issued).
  int? validityMinutesLeft(DateTime now) =>
      validUntil == null ? null : validUntil!.difference(now).inMinutes;

  static List<PermitSummary> listFromJson(dynamic json) =>
      unwrapList(json).map(PermitSummary.fromJson).toList();

  factory PermitSummary.fromJson(Map<String, dynamic> json) => PermitSummary(
    id: json['id']?.toString() ?? '',
    permitNo: firstNonEmpty([json['permitNo']]) ?? '',
    type: json['type']?.toString() ?? 'general',
    secondaryTypes: json['secondaryTypes'] is List
        ? (json['secondaryTypes'] as List).map((e) => e.toString()).toList()
        : const [],
    status: json['status']?.toString() ?? 'draft',
    title: firstNonEmpty([json['title']]) ?? 'Permit',
    buildingId: firstNonEmpty([json['buildingId']]),
    buildingName: firstNonEmpty([json['buildingName']]),
    floorId: firstNonEmpty([json['floorId']]),
    floorName: firstNonEmpty([json['floorName']]),
    zoneId: firstNonEmpty([json['zoneId']]),
    zoneName: firstNonEmpty([json['zoneName']]),
    spaceId: firstNonEmpty([json['spaceId']]),
    spaceName: firstNonEmpty([json['spaceName']]),
    locationNote: firstNonEmpty([json['locationNote']]),
    assetId: firstNonEmpty([json['assetId']]),
    assetName: firstNonEmpty([json['assetName']]),
    workOrderId: firstNonEmpty([json['workOrderId']]),
    workOrderRef: firstNonEmpty([json['workOrderRef']]),
    requestedBy: firstNonEmpty([json['requestedBy']]),
    requestedByName: firstNonEmpty([json['requestedByName']]),
    contractorCompany: firstNonEmpty([json['contractorCompany']]),
    supervisorName: firstNonEmpty([json['supervisorName']]),
    plannedStart: asDate(json['plannedStart']),
    plannedEnd: asDate(json['plannedEnd']),
    issuedAt: asDate(json['issuedAt']),
    validUntil: asDate(json['validUntil']),
    completedAt: asDate(json['completedAt']),
    closedAt: asDate(json['closedAt']),
    riskScore: asDouble(json['riskScore']) ?? 0,
    riskLevel: firstNonEmpty([json['riskLevel']]) ?? 'low',
    currentStage: PermitStage.fromJson(json['currentStage']),
    crewOnSite: asInt(json['crewOnSite']) ?? 0,
    isolationsLive: asInt(json['isolationsLive']) ?? 0,
    gasLastResult: firstNonEmpty([json['gasLastResult']]),
    fireWatchEndsAt: asDate(json['fireWatchEndsAt']),
    flags: PermitFlags.fromJson(json['flags']),
    conflictCount: asInt(json['conflictCount']) ?? 0,
    maxConflictSeverity: firstNonEmpty([json['maxConflictSeverity']]),
    createdAt: asDate(json['createdAt']) ?? DateTime.now(),
    updatedAt: asDate(json['updatedAt']) ?? DateTime.now(),
  );
}

/// The full permit — everything the detail screen and its sheets need.
class PermitDetail extends PermitSummary {
  const PermitDetail({
    required super.id,
    required super.permitNo,
    required super.type,
    super.secondaryTypes,
    required super.status,
    required super.title,
    super.buildingId,
    super.buildingName,
    super.floorId,
    super.floorName,
    super.zoneId,
    super.zoneName,
    super.spaceId,
    super.spaceName,
    super.locationNote,
    super.assetId,
    super.assetName,
    super.workOrderId,
    super.workOrderRef,
    super.requestedBy,
    super.requestedByName,
    super.contractorCompany,
    super.supervisorName,
    super.plannedStart,
    super.plannedEnd,
    super.issuedAt,
    super.validUntil,
    super.completedAt,
    super.closedAt,
    super.riskScore,
    super.riskLevel,
    super.currentStage,
    super.crewOnSite,
    super.isolationsLive,
    super.gasLastResult,
    super.fireWatchEndsAt,
    super.flags,
    super.conflictCount,
    super.maxConflictSeverity,
    required super.createdAt,
    required super.updatedAt,
    this.description,
    this.pmId,
    this.vendorId,
    this.supervisorPhone,
    this.riskLikelihood = 1,
    this.riskSeverity = 1,
    this.hazards = const [],
    this.controls = const [],
    this.ppe = const [],
    this.approvals = const [],
    this.checks = const {},
    this.closeChecks = const {},
    this.fireWatch,
    this.qrToken = '',
    this.attachments = const [],
    this.activity = const [],
    this.isolations = const [],
    this.gasTests = const [],
    this.crew = const [],
    this.readiness = PermitReadiness.empty,
    this.checklistPre = const [],
    this.checklistClose = const [],
    this.gasProfile = GasProfile.empty,
    this.effective = PermitEffective.empty,
  });

  final String? description;
  final String? pmId;
  final String? vendorId;
  final String? supervisorPhone;
  final num riskLikelihood;
  final num riskSeverity;

  /// Catalogue ids, or free text for a custom entry — render through
  /// `PermitCatalog.hazardLabel` etc, falling back to the raw id.
  final List<String> hazards;
  final List<String> controls;
  final List<String> ppe;
  final List<PermitApproval> approvals;
  final Map<String, PermitCheckState> checks;
  final Map<String, PermitCheckState> closeChecks;
  final PermitFireWatch? fireWatch;
  final String qrToken;
  final List<PermitAttachment> attachments;
  final List<PermitActivity> activity;
  final List<PermitIsolation> isolations;
  final List<PermitGasTest> gasTests;
  final List<PermitCrew> crew;
  final PermitReadiness readiness;
  final List<PermitCheckDef> checklistPre;
  final List<PermitCheckDef> checklistClose;

  /// The limits a gas test on this permit is judged against.
  final GasProfile gasProfile;
  final PermitEffective effective;

  /// This session's crew row, if the signed-in technician is on the crew —
  /// the row the detail screen lets them sign on/off.
  PermitCrew? myCrew(String? sessionUserId) {
    for (final c in crew) {
      if (c.isMe(sessionUserId)) return c;
    }
    return null;
  }

  PermitGasTest? get latestGasTest => gasTests.isEmpty ? null : gasTests.first;

  static PermitDetail? fromJsonOrNull(dynamic json) {
    final m = unwrapMap(json);
    return m.isEmpty ? null : PermitDetail.fromJson(m);
  }

  factory PermitDetail.fromJson(Map<String, dynamic> json) {
    final summary = PermitSummary.fromJson(json);
    List<T> list<T>(dynamic v, T Function(Map<String, dynamic>) parse) => v is List
        ? v.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList()
        : <T>[];
    return PermitDetail(
      id: summary.id,
      permitNo: summary.permitNo,
      type: summary.type,
      secondaryTypes: summary.secondaryTypes,
      status: summary.status,
      title: summary.title,
      buildingId: summary.buildingId,
      buildingName: summary.buildingName,
      floorId: summary.floorId,
      floorName: summary.floorName,
      zoneId: summary.zoneId,
      zoneName: summary.zoneName,
      spaceId: summary.spaceId,
      spaceName: summary.spaceName,
      locationNote: summary.locationNote,
      assetId: summary.assetId,
      assetName: summary.assetName,
      workOrderId: summary.workOrderId,
      workOrderRef: summary.workOrderRef,
      requestedBy: summary.requestedBy,
      requestedByName: summary.requestedByName,
      contractorCompany: summary.contractorCompany,
      supervisorName: summary.supervisorName,
      plannedStart: summary.plannedStart,
      plannedEnd: summary.plannedEnd,
      issuedAt: summary.issuedAt,
      validUntil: summary.validUntil,
      completedAt: summary.completedAt,
      closedAt: summary.closedAt,
      riskScore: summary.riskScore,
      riskLevel: summary.riskLevel,
      currentStage: summary.currentStage,
      crewOnSite: summary.crewOnSite,
      isolationsLive: summary.isolationsLive,
      gasLastResult: summary.gasLastResult,
      fireWatchEndsAt: summary.fireWatchEndsAt,
      flags: summary.flags,
      conflictCount: summary.conflictCount,
      maxConflictSeverity: summary.maxConflictSeverity,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      description: firstNonEmpty([json['description']]),
      pmId: firstNonEmpty([json['pmId']]),
      vendorId: firstNonEmpty([json['vendorId']]),
      supervisorPhone: firstNonEmpty([json['supervisorPhone']]),
      riskLikelihood: asDouble(json['riskLikelihood']) ?? 1,
      riskSeverity: asDouble(json['riskSeverity']) ?? 1,
      hazards: json['hazards'] is List ? (json['hazards'] as List).map((e) => e.toString()).toList() : const [],
      controls: json['controls'] is List ? (json['controls'] as List).map((e) => e.toString()).toList() : const [],
      ppe: json['ppe'] is List ? (json['ppe'] as List).map((e) => e.toString()).toList() : const [],
      approvals: list(json['approvals'], PermitApproval.fromJson),
      checks: PermitCheckState.mapFromJson(json['checks']),
      closeChecks: PermitCheckState.mapFromJson(json['closeChecks']),
      fireWatch: PermitFireWatch.fromJson(json['fireWatch']),
      qrToken: json['qrToken']?.toString() ?? '',
      attachments: list(json['attachments'], PermitAttachment.fromJson),
      activity: list(json['activity'], PermitActivity.fromJson),
      isolations: list(json['isolations'], PermitIsolation.fromJson),
      gasTests: list(json['gasTests'], PermitGasTest.fromJson),
      crew: list(json['crew'], PermitCrew.fromJson),
      readiness: PermitReadiness.fromJson(json['readiness']),
      checklistPre: json['checklist'] is Map
          ? PermitCheckDef.listFromJson((json['checklist'] as Map)['pre'])
          : const [],
      checklistClose: json['checklist'] is Map
          ? PermitCheckDef.listFromJson((json['checklist'] as Map)['close'])
          : const [],
      gasProfile: GasProfile.fromJson(json['gasProfile']),
      effective: PermitEffective.fromJson(json['effective']),
    );
  }
}

// ---------------------------------------------------------------- catalogue

class PermitCrewRoleDef {
  const PermitCrewRoleDef({required this.key, required this.label});
  final String key;
  final String label;

  factory PermitCrewRoleDef.fromJson(Map<String, dynamic> json) => PermitCrewRoleDef(
    key: json['key']?.toString() ?? '',
    label: firstNonEmpty([json['label']]) ?? '',
  );
}

class PermitTypeDef {
  const PermitTypeDef({
    required this.key,
    required this.label,
    this.code,
    this.summary,
    this.gas,
    this.fireWatchMinutes = 0,
    this.requiresIsolation = false,
    this.requiredRoles = const [],
  });

  final String key;
  final String label;
  final String? code;
  final String? summary;
  final GasProfile? gas;
  final int fireWatchMinutes;
  final bool requiresIsolation;
  final List<String> requiredRoles;

  factory PermitTypeDef.fromJson(Map<String, dynamic> json) => PermitTypeDef(
    key: json['key']?.toString() ?? '',
    label: firstNonEmpty([json['label']]) ?? json['key']?.toString() ?? '',
    code: firstNonEmpty([json['code']]),
    summary: firstNonEmpty([json['summary']]),
    gas: json['gas'] == null ? null : GasProfile.fromJson(json['gas']),
    fireWatchMinutes: asInt(json['fireWatchMinutes']) ?? 0,
    requiresIsolation: asBool(json['requiresIsolation']) ?? false,
    requiredRoles: json['requiredRoles'] is List
        ? (json['requiredRoles'] as List).map((e) => e.toString()).toList()
        : const [],
  );
}

/// Labels for hazards/controls/PPE/roles/types (`GET /api/fm/permits/catalog`).
/// Cache this — it changes rarely and every briefing/isolation sheet needs
/// it to turn a catalogue id into readable text.
class PermitCatalog {
  const PermitCatalog({
    this.types = const [],
    this.hazards = const {},
    this.controls = const {},
    this.ppe = const {},
    this.crewRoles = const [],
    this.gasLimits = const {},
  });

  final List<PermitTypeDef> types;
  final Map<String, String> hazards;
  final Map<String, String> controls;
  final Map<String, String> ppe;
  final List<PermitCrewRoleDef> crewRoles;
  final Map<String, GasLimit> gasLimits;

  static const empty = PermitCatalog();

  String hazardLabel(String id) => hazards[id] ?? id;
  String controlLabel(String id) => controls[id] ?? id;
  String ppeLabel(String id) => ppe[id] ?? id;

  String roleLabel(String key) {
    for (final r in crewRoles) {
      if (r.key == key) return r.label;
    }
    return key;
  }

  PermitTypeDef? typeDef(String key) {
    for (final t in types) {
      if (t.key == key) return t;
    }
    return null;
  }

  String typeLabel(String key) => typeDef(key)?.label ?? key;

  factory PermitCatalog.fromJson(dynamic json) {
    final m = unwrapMap(json);
    Map<String, String> strMap(dynamic v) =>
        v is Map ? {for (final e in v.entries) e.key.toString(): e.value.toString()} : const {};
    return PermitCatalog(
      types: m['types'] is List
          ? (m['types'] as List).whereType<Map>().map((e) => PermitTypeDef.fromJson(Map<String, dynamic>.from(e))).toList()
          : const [],
      hazards: strMap(m['hazards']),
      controls: strMap(m['controls']),
      ppe: strMap(m['ppe']),
      crewRoles: m['crewRoles'] is List
          ? (m['crewRoles'] as List)
                .whereType<Map>()
                .map((e) => PermitCrewRoleDef.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      gasLimits: m['gasLimits'] is Map
          ? {
              for (final e in (m['gasLimits'] as Map).entries)
                if (e.value is Map) e.key.toString(): GasLimit.fromJson(Map<String, dynamic>.from(e.value as Map)),
            }
          : const {},
    );
  }
}
