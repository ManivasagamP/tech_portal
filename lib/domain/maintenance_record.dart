import '../core/network/envelope.dart';
import 'checklist.dart';

/// The four record kinds a technician can be assigned. Path vocabularies differ
/// per kind and are not derivable from the slug — work orders pluralise for RCA
/// and downtime while the maintenance kinds do not, so the table is hard-coded.
enum OrderType {
  workOrder(
    slug: 'work-order',
    label: 'Work Order',
    entityPath: 'work-order',
    rcaPath: 'work-orders',
    downtimePath: 'work-orders',
    completePath: 'work-order',
    downtimeSource: 'work-order',
    historyType: null,
  ),
  preventive(
    slug: 'preventive',
    label: 'Preventive Maintenance',
    entityPath: 'preventive-maintenance',
    rcaPath: 'preventive-maintenance',
    downtimePath: 'preventive-maintenance',
    completePath: 'preventive-maintenance',
    downtimeSource: 'preventive',
    historyType: 'Preventive',
  ),
  reactive(
    slug: 'reactive',
    label: 'Reactive Maintenance',
    entityPath: 'reactive-maintenance',
    rcaPath: 'reactive-maintenance',
    downtimePath: 'reactive-maintenance',
    completePath: 'reactive-maintenance',
    downtimeSource: 'reactive',
    historyType: 'Reactive',
  ),
  annual(
    slug: 'annual',
    label: 'Annual Maintenance',
    entityPath: 'annual-maintenance',
    rcaPath: 'annual-maintenance',
    downtimePath: 'annual-maintenance',
    completePath: 'annual-maintenance',
    downtimeSource: 'annual',
    historyType: 'Annual',
  );

  const OrderType({
    required this.slug,
    required this.label,
    required this.entityPath,
    required this.rcaPath,
    required this.downtimePath,
    required this.completePath,
    required this.downtimeSource,
    required this.historyType,
  });

  /// Route segment, matching the web `/technician/orders/{slug}/{id}`.
  final String slug;
  final String label;
  final String entityPath;
  final String rcaPath;
  final String downtimePath;

  /// The value `GET /api/fm/assets/{id}/downtime` stamps on each row, used to
  /// tell this record's own open window from another record's. It matches the
  /// route slug today, but it is a separate server vocabulary and is spelled
  /// out rather than derived.
  final String downtimeSource;
  final String completePath;

  /// Work orders have no history endpoint.
  final String? historyType;

  String get listPath => '/api/fm/$entityPath/technician';
  String get checklistPath => entityPath;

  static OrderType fromSlug(String? slug) => switch (slug) {
        'preventive' => OrderType.preventive,
        'reactive' => OrderType.reactive,
        'annual' => OrderType.annual,
        _ => OrderType.workOrder,
      };
}

/// The three kinds a technician actually browses. Preventive is excluded: a PM
/// schedule is never a task by itself — the workable thing is the work order the
/// PM cron generates from it. PM detail stays reachable from an invite tap.
const kBrowsableOrderTypes = [
  OrderType.workOrder,
  OrderType.reactive,
  OrderType.annual,
];

class AssignmentChainEntry {
  const AssignmentChainEntry({
    required this.technicianId,
    required this.technicianName,
    required this.sequenceOrder,
    required this.status,
    this.declineReason,
    this.invitedAt,
    this.respondedAt,
  });

  final String technicianId;
  final String technicianName;
  final int sequenceOrder;
  final String status;
  final String? declineReason;
  final DateTime? invitedAt;
  final DateTime? respondedAt;

  factory AssignmentChainEntry.fromJson(Map<String, dynamic> json) =>
      AssignmentChainEntry(
        technicianId: json['technicianId']?.toString() ?? '',
        technicianName: json['technicianName']?.toString() ?? '',
        sequenceOrder: asInt(json['sequenceOrder']) ?? 0,
        status: json['status']?.toString() ?? 'pending',
        declineReason: json['declineReason']?.toString(),
        invitedAt: asDate(json['invitedAt']),
        respondedAt: asDate(json['respondedAt']),
      );
}

/// One façade over the four record shapes so list and detail widgets stay
/// generic. Field names differ per kind on the wire; the fallback chains here
/// are the ones the web renderers use.
class MaintenanceRecord {
  const MaintenanceRecord({
    required this.raw,
    required this.id,
    required this.type,
    this.referenceId,
    this.titleField,
    this.subRequest,
    this.assetName,
    this.description,
    this.taskDescription,
    this.priority,
    this.status,
    this.location,
    this.department,
    this.category,
    this.effectiveDate,
    this.startedDate,
    this.completedDate,
    this.estimatedHours,
    this.actualHours,
    this.assetId,
    this.technicianName,
    this.checklists = const [],
    this.checklistMandatory,
    this.requireFaceCapture = false,
    this.requireLocation = false,
    this.assignmentStatus,
    this.assignmentChain = const [],
    this.notesAudioUrl,
    this.frequency,
    this.urgency,
    this.contractValue,
  });

  /// The server row as received, so detail writes can patch without dropping
  /// fields this app does not model.
  final Map<String, dynamic> raw;

  final String id;
  final OrderType type;
  final String? referenceId;

  final String? titleField;
  final String? subRequest;
  final String? assetName;
  final String? description;
  final String? taskDescription;

  final String? priority;
  final String? status;
  final String? location;
  final String? department;
  final String? category;

  final DateTime? effectiveDate;
  final DateTime? startedDate;
  final DateTime? completedDate;
  final double? estimatedHours;
  final double? actualHours;

  final String? assetId;
  final String? technicianName;

  final List<ChecklistItem> checklists;

  /// Null means mandatory for the maintenance kinds; work orders default to
  /// optional instead.
  final bool? checklistMandatory;
  final bool requireFaceCapture;
  final bool requireLocation;

  final String? assignmentStatus;
  final List<AssignmentChainEntry> assignmentChain;

  final String? notesAudioUrl;
  final String? frequency;
  final String? urgency;
  final double? contractValue;

  bool get isChecklistMandatory =>
      checklistMandatory ?? (type != OrderType.workOrder);

  bool get isAssignmentPending => assignmentStatus == 'pending';

  /// Card title. The orders list prefers the asset over the record's own title,
  /// because a reactive ticket's `title` is often the raw complaint text.
  String get cardTitle =>
      firstNonEmpty([subRequest, assetName, titleField]) ?? 'Untitled Task';

  /// Dashboard title. Deliberately a different chain from [cardTitle] — the
  /// dashboard leads with the record's own title.
  String get focusTitle =>
      firstNonEmpty([titleField, description, assetName]) ?? 'Untitled Task';

  String get cardDescription =>
      firstNonEmpty([description, taskDescription]) ?? 'No description provided';

  String get displayPriority {
    final p = priority?.trim();
    if (p == null || p.isEmpty) return 'Medium';
    return p[0].toUpperCase() + p.substring(1).toLowerCase();
  }

  String get displayStatus => firstNonEmpty([status]) ?? 'Pending';

  String get displayLocation => firstNonEmpty([location]) ?? 'Unknown';

  String get displayTechnician =>
      firstNonEmpty([technicianName]) ?? 'Unassigned';

  /// Lowercased with hyphens flattened, the shape both the status filter and
  /// the overdue guard compare against.
  String get normalizedStatus =>
      (status ?? '').toLowerCase().replaceFirst('-', ' ');

  factory MaintenanceRecord.fromJson(
    Map<String, dynamic> json, [
    OrderType? type,
  ]) {
    final asset = json['asset'];
    final assetMap = asset is Map ? Map<String, dynamic>.from(asset) : const {};

    final chain = json['assignmentChain'];
    final entries = chain is List
        ? chain
            .whereType<Map>()
            .map((e) =>
                AssignmentChainEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <AssignmentChainEntry>[];

    return MaintenanceRecord(
      raw: json,
      id: json['id']?.toString() ?? '',
      type: type ?? inferType(json),
      referenceId: firstNonEmpty([
        json['workOrderId'],
        json['pmScheduleId'],
        json['ticketId'],
        json['amcScheduleId'],
      ]),
      titleField: json['title']?.toString(),
      subRequest: json['subRequest']?.toString(),
      assetName: firstNonEmpty([assetMap['name'], json['assetName']]),
      description: json['description']?.toString(),
      taskDescription: json['taskDescription']?.toString(),
      priority: json['priority']?.toString(),
      status: json['status']?.toString(),
      location: json['location']?.toString(),
      department: json['department']?.toString(),
      category: json['category']?.toString(),
      effectiveDate:
          asDate(json['dueDate'] ?? json['plannedDate'] ?? json['dateTime']),
      startedDate: asDate(json['startedDate']),
      completedDate: asDate(json['completedDate']),
      estimatedHours: asDouble(json['estimatedHours']),
      actualHours: asDouble(json['actualHours']),
      assetId: firstNonEmpty([json['relatedAssetId'], json['assetId']]),
      technicianName: firstNonEmpty([
        json['technicianName'],
        json['assignedTechnician'],
        json['technicianId'],
      ]),
      checklists: ChecklistItem.listFrom(json['checklists']),
      checklistMandatory: asBool(json['checklistMandatory']),
      requireFaceCapture: asBool(json['requireFaceCapture']) ?? false,
      requireLocation: asBool(json['requireLocation']) ?? false,
      assignmentStatus: json['assignmentStatus']?.toString(),
      assignmentChain: entries,
      notesAudioUrl: json['notesAudioUrl']?.toString(),
      frequency: json['frequency']?.toString(),
      urgency: json['urgency']?.toString(),
      contractValue: asDouble(json['contractValue']),
    );
  }

  /// Which kind a row is, by which reference id it carries. Only needed when a
  /// list mixes kinds; a single-type fetch already knows.
  static OrderType inferType(Map<String, dynamic> json) {
    if (firstNonEmpty([json['workOrderId']]) != null) return OrderType.workOrder;
    if (firstNonEmpty([json['ticketId']]) != null) return OrderType.reactive;
    if (firstNonEmpty([json['amcScheduleId']]) != null) return OrderType.annual;
    if (firstNonEmpty([json['pmScheduleId']]) != null) {
      return OrderType.preventive;
    }
    return OrderType.workOrder;
  }

  /// [type] is passed when the caller already knows the kind from the endpoint
  /// it fetched. That beats inference, which has nothing to go on when a row is
  /// missing its reference id and would silently call it a work order.
  static List<MaintenanceRecord> listFrom(
    List<Map<String, dynamic>> rows, [
    OrderType? type,
  ]) =>
      rows.map((row) => MaintenanceRecord.fromJson(row, type)).toList();
}
