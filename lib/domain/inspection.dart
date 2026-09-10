import '../core/network/envelope.dart';

/// Field kinds. Mirrors the web's wider `FieldType` union (`FormBuilder.tsx`)
/// almost completely — the two exceptions are deliberate, not gaps:
/// [columns] falls into [unsupported] because the web's own FormRenderer has
/// no case for it either (dead builder-only concept, no parent/child nesting
/// exists in the schema at all); [button] is modeled but never rendered as a
/// field — see `InspectionFormScreen._submitLabel`.
enum InspectionFieldType {
  text,
  textarea,
  number,
  checkbox,
  select,
  radio,
  date,
  photo,
  signature,
  selectboxes,
  file,
  survey,
  rating,
  panel,
  html,
  button,
  unsupported;

  static InspectionFieldType fromWire(String? wire) => switch (wire) {
    'textfield' => InspectionFieldType.text,
    'textarea' => InspectionFieldType.textarea,
    'number' => InspectionFieldType.number,
    'checkbox' => InspectionFieldType.checkbox,
    'select' => InspectionFieldType.select,
    'radio' => InspectionFieldType.radio,
    'datetime' => InspectionFieldType.date,
    'photo' => InspectionFieldType.photo,
    'signature' => InspectionFieldType.signature,
    'selectboxes' => InspectionFieldType.selectboxes,
    'file' => InspectionFieldType.file,
    'survey' => InspectionFieldType.survey,
    'rating' => InspectionFieldType.rating,
    'panel' => InspectionFieldType.panel,
    'html' => InspectionFieldType.html,
    'button' => InspectionFieldType.button,
    _ => InspectionFieldType.unsupported, // includes 'columns'
  };
}

class InspectionFieldOption {
  const InspectionFieldOption({required this.label, required this.value});

  final String label;
  final String value;

  factory InspectionFieldOption.fromJson(Map<String, dynamic> json) =>
      InspectionFieldOption(
        label: json['label']?.toString() ?? '',
        value: json['value']?.toString() ?? '',
      );

  static List<InspectionFieldOption> listFrom(dynamic raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((o) => InspectionFieldOption.fromJson(Map<String, dynamic>.from(o)))
            .toList()
      : const [];
}

class InspectionField {
  const InspectionField({
    required this.id,
    required this.type,
    required this.label,
    required this.key,
    this.required = false,
    this.placeholder,
    this.description,
    this.options = const [],
    this.multiple = false,
    this.starCount = 5,
    this.surveyRows = const [],
    this.surveyColumns = const [],
    this.panelTitle,
    this.htmlContent,
    this.maxPhotos = 5,
    this.allowGallery = false,
    this.requireGeotag = false,
    this.compressToWidth = 1600,
    this.signerNameField = true,
    this.penColor = '#111111',
    this.requireName = true,
    this.aiAnalyse = false,
    this.aiAllowGallery = false,
  });

  final String id;
  final InspectionFieldType type;
  final String label;
  final String key;
  final bool required;
  final String? placeholder;
  final String? description;
  final List<InspectionFieldOption> options;

  // file
  final bool multiple;
  final bool aiAnalyse;
  final bool aiAllowGallery;

  // rating
  final int starCount;

  // survey
  final List<InspectionFieldOption> surveyRows;
  final List<InspectionFieldOption> surveyColumns;

  // panel
  final String? panelTitle;

  // html
  final String? htmlContent;

  // photo
  final int maxPhotos;
  final bool allowGallery;
  final bool requireGeotag;
  final int compressToWidth;

  // signature
  final bool signerNameField;
  final String penColor;
  final bool requireName;

  /// Copy with an overridden [required] — the only mutation the conditional-
  /// logic engine ever needs (a `require`/`unrequire` action never changes
  /// anything else about a field).
  InspectionField copyWithRequired(bool required) => InspectionField(
    id: id,
    type: type,
    label: label,
    key: key,
    required: required,
    placeholder: placeholder,
    description: description,
    options: options,
    multiple: multiple,
    starCount: starCount,
    surveyRows: surveyRows,
    surveyColumns: surveyColumns,
    panelTitle: panelTitle,
    htmlContent: htmlContent,
    maxPhotos: maxPhotos,
    allowGallery: allowGallery,
    requireGeotag: requireGeotag,
    compressToWidth: compressToWidth,
    signerNameField: signerNameField,
    penColor: penColor,
    requireName: requireName,
    aiAnalyse: aiAnalyse,
    aiAllowGallery: aiAllowGallery,
  );

  factory InspectionField.fromJson(Map<String, dynamic> json) =>
      InspectionField(
        id: json['id']?.toString() ?? '',
        type: InspectionFieldType.fromWire(json['type']?.toString()),
        label: json['label']?.toString() ?? '',
        key: json['key']?.toString() ?? '',
        required: asBool(json['required']) ?? false,
        placeholder: json['placeholder']?.toString(),
        description: json['description']?.toString(),
        options: InspectionFieldOption.listFrom(json['options']),
        multiple: asBool(json['multiple']) ?? false,
        starCount: asInt(json['starCount']) ?? 5,
        surveyRows: InspectionFieldOption.listFrom(json['surveyRows']),
        surveyColumns: InspectionFieldOption.listFrom(json['surveyColumns']),
        panelTitle: json['panelTitle']?.toString(),
        htmlContent: json['htmlContent']?.toString(),
        maxPhotos: asInt(json['maxPhotos']) ?? 5,
        allowGallery: asBool(json['allowGallery']) ?? false,
        requireGeotag: asBool(json['requireGeotag']) ?? false,
        compressToWidth: asInt(json['compressToWidth']) ?? 1600,
        signerNameField: asBool(json['signerNameField']) ?? true,
        penColor: json['penColor']?.toString() ?? '#111111',
        requireName: asBool(json['requireName']) ?? true,
        aiAnalyse: asBool(json['aiAnalyse']) ?? false,
        aiAllowGallery: asBool(json['aiAllowGallery']) ?? false,
      );
}

/// One condition + one action — the web builder only ever produces a single
/// condition/action pair per rule (`ConditionalRule.conditions`/`.actions`
/// are typed as 1-tuples client-side), and `FormRenderer.tsx`'s evaluator
/// only ever reads index 0 of each, so this models what's actually evaluated
/// rather than the redundant array wrapper.
class ConditionalRule {
  const ConditionalRule({
    required this.enabled,
    required this.conditionFieldId,
    required this.operatorName,
    required this.conditionValue,
    required this.actionEnabled,
    required this.actionType,
    this.actionFieldId,
  });

  final bool enabled;
  final String conditionFieldId;
  final String operatorName;
  final String conditionValue;
  final bool actionEnabled;
  final String actionType; // show | hide | require | unrequire | email_admin
  final String? actionFieldId;

  factory ConditionalRule.fromJson(Map<String, dynamic> json) {
    final conditions = json['conditions'];
    final condition = conditions is List && conditions.isNotEmpty && conditions.first is Map
        ? Map<String, dynamic>.from(conditions.first as Map)
        : const <String, dynamic>{};
    final actions = json['actions'];
    final action = actions is List && actions.isNotEmpty && actions.first is Map
        ? Map<String, dynamic>.from(actions.first as Map)
        : const <String, dynamic>{};

    return ConditionalRule(
      enabled: asBool(json['enabled']) ?? true,
      conditionFieldId: condition['fieldId']?.toString() ?? '',
      operatorName: condition['operator']?.toString() ?? '',
      conditionValue: condition['value']?.toString() ?? '',
      actionEnabled: asBool(action['enabled']) ?? true,
      actionType: action['type']?.toString() ?? '',
      actionFieldId: action['fieldId']?.toString(),
    );
  }
}

/// Form-level settings from the schema's `_fms` map (`InspectionDetails` on
/// the web). `supervisorApproval` is deliberately not modeled — confirmed
/// dead (read nowhere client or server side, its builder toggle is
/// commented out).
class InspectionFormDetails {
  const InspectionFormDetails({
    this.gpsRequired = false,
    this.timerEnabled = false,
    this.supervisorSignature = false,
  });

  final bool gpsRequired;
  final bool timerEnabled;
  final bool supervisorSignature;

  factory InspectionFormDetails.fromJson(dynamic raw) {
    final json = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return InspectionFormDetails(
      gpsRequired: asBool(json['gpsRequired']) ?? false,
      timerEnabled: asBool(json['timerEnabled']) ?? false,
      supervisorSignature: asBool(json['supervisorSignature']) ?? false,
    );
  }
}

/// The inspection template's checklist definition — a port of the web's
/// `FormSchema`/`FormField` (`FormBuilder.tsx`).
class InspectionSchema {
  const InspectionSchema({
    required this.title,
    required this.components,
    required this.conditionalRules,
    required this.details,
  });

  final String title;
  final List<InspectionField> components;
  final List<ConditionalRule> conditionalRules;
  final InspectionFormDetails details;

  /// Fields any enabled rule's action targets — used by the server-mirrored
  /// required-field skip (`InspectionDetailController.missingRequiredFields`)
  /// and by the conditional-logic engine's default-visibility rule.
  Set<String> get conditionalFieldIds => {
    for (final rule in conditionalRules)
      if (rule.enabled && rule.actionFieldId != null && rule.actionFieldId!.isNotEmpty)
        rule.actionFieldId!,
  };

  /// The first `button`-type component's label, if the schema has one — the
  /// only thing a `button` field contributes (it's never rendered itself).
  String? get submitButtonLabel {
    for (final field in components) {
      if (field.type == InspectionFieldType.button && field.label.isNotEmpty) {
        return field.label;
      }
    }
    return null;
  }

  InspectionField? fieldById(String id) {
    for (final field in components) {
      if (field.id == id) return field;
    }
    return null;
  }

  factory InspectionSchema.fromJson(Map<String, dynamic> json) {
    final components = json['components'] is List
        ? (json['components'] as List)
              .whereType<Map>()
              .map((c) => InspectionField.fromJson(Map<String, dynamic>.from(c)))
              .toList()
        : const <InspectionField>[];

    final rules = json['conditionalRules'];
    final conditionalRules = rules is List
        ? rules
              .whereType<Map>()
              .map((r) => ConditionalRule.fromJson(Map<String, dynamic>.from(r)))
              .toList()
        : const <ConditionalRule>[];

    return InspectionSchema(
      title: json['title']?.toString() ?? '',
      components: components,
      conditionalRules: conditionalRules,
      details: InspectionFormDetails.fromJson(json['_fms']),
    );
  }
}

/// One row of `GET /api/fm/inspections/technician/assigned` — enough to
/// render the list without fetching every assignment's full schema.
class InspectionAssignmentSummary {
  const InspectionAssignmentSummary({
    required this.id,
    required this.referenceId,
    required this.status,
    this.dueDate,
    this.templateName,
    this.templateLocation,
  });

  final String id;
  final String referenceId;
  final String status;
  final DateTime? dueDate;
  final String? templateName;
  final String? templateLocation;

  bool get isOverdue =>
      status == 'pending' && dueDate != null && dueDate!.isBefore(DateTime.now());

  factory InspectionAssignmentSummary.fromJson(Map<String, dynamic> json) {
    final template = json['template'];
    final templateMap = template is Map
        ? Map<String, dynamic>.from(template)
        : const <String, dynamic>{};
    return InspectionAssignmentSummary(
      id: json['id']?.toString() ?? '',
      referenceId: json['referenceId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      dueDate: asDate(json['dueDate']),
      templateName: templateMap['name']?.toString(),
      templateLocation: templateMap['location']?.toString(),
    );
  }
}

/// `GET /api/fm/inspections/technician/:id` — the full assignment plus the
/// template's schema, what `InspectionFormScreen` renders and fills in.
class InspectionAssignmentDetail {
  const InspectionAssignmentDetail({
    required this.assignmentId,
    required this.referenceId,
    required this.status,
    required this.templateName,
    required this.schema,
    this.templateDescription,
    this.dueDate,
    this.responseData = const {},
  });

  final String assignmentId;
  final String referenceId;
  final String status;
  final String templateName;
  final String? templateDescription;
  final DateTime? dueDate;
  final InspectionSchema schema;
  final Map<String, dynamic> responseData;

  factory InspectionAssignmentDetail.fromJson(Map<String, dynamic> json) {
    final schema = json['schema'];
    return InspectionAssignmentDetail(
      assignmentId: json['assignmentId']?.toString() ?? '',
      referenceId: json['referenceId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      templateName: json['templateName']?.toString() ?? 'Inspection',
      templateDescription: json['templateDescription']?.toString(),
      dueDate: asDate(json['dueDate']),
      schema: InspectionSchema.fromJson(
        schema is Map ? Map<String, dynamic>.from(schema) : const {},
      ),
      responseData: json['responseData'] is Map
          ? Map<String, dynamic>.from(json['responseData'])
          : const {},
    );
  }
}
