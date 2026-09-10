import '../../domain/inspection.dart';

/// Port of `evaluateCondition` + the `visibleFields` useMemo in the web's
/// `FormRenderer.tsx`. Two entry points: [computeFieldStates] (visibility +
/// effective-required per field id) and [visibleFieldsFor] (the filtered,
/// required-patched component list the form screen actually renders).

class FieldState {
  FieldState({required this.visible, required this.required});
  bool visible;
  bool required;
}

/// [answers] is keyed by `field.key` (as everywhere else in this app);
/// `condition.fieldId` refers to a component **id**, so this resolves id →
/// key the same two-step way the web does before reading a value.
dynamic _lookupValue(String fieldId, InspectionSchema schema, Map<String, dynamic> answers) {
  if (answers.containsKey(fieldId)) return answers[fieldId];
  final field = schema.fieldById(fieldId);
  if (field == null) return null;
  return answers[field.key];
}

/// True if a photo/signature-shaped answer (`{values:[...]}`) has at least
/// one item — pending (not-yet-uploaded) items count as "has", same as the
/// web (`FormRenderer.tsx`'s `has photo`/`has signature` operators). This is
/// deliberately more permissive than "required satisfied"
/// (`InspectionDetailController.missingRequiredFields`, which only counts
/// `uploadStatus == 'uploaded'`) — keep the two checks distinct.
bool _hasMediaItems(dynamic value) {
  if (value is Map && value['values'] is List) {
    return (value['values'] as List).isNotEmpty;
  }
  if (value is List) return value.isNotEmpty;
  return false;
}

bool evaluateCondition(
  ConditionalRule rule,
  InspectionSchema schema,
  Map<String, dynamic> answers,
) {
  final actual = _lookupValue(rule.conditionFieldId, schema, answers);
  final target = rule.conditionValue;

  String s(dynamic v) => (v ?? '').toString();

  switch (rule.operatorName) {
    case 'equals':
      return s(actual) == target;
    case 'not equals':
      return s(actual) != target;
    case 'contains':
      return s(actual).toLowerCase().contains(target.toLowerCase());
    case 'starts with':
      return s(actual).toLowerCase().startsWith(target.toLowerCase());
    case 'ends with':
      return s(actual).toLowerCase().endsWith(target.toLowerCase());
    case 'is empty':
      return actual == null || s(actual).isEmpty;
    case 'is not empty':
      return !(actual == null || s(actual).isEmpty);
    case 'greater than':
      return (num.tryParse(s(actual)) ?? double.nan) > (num.tryParse(target) ?? double.nan);
    case 'less than':
      return (num.tryParse(s(actual)) ?? double.nan) < (num.tryParse(target) ?? double.nan);
    case 'greater or equal':
      return (num.tryParse(s(actual)) ?? double.nan) >= (num.tryParse(target) ?? double.nan);
    case 'less or equal':
      return (num.tryParse(s(actual)) ?? double.nan) <= (num.tryParse(target) ?? double.nan);
    case 'is checked':
      return actual == true || s(actual) == 'true';
    case 'is unchecked':
      return actual == false || s(actual) == 'false';
    case 'includes':
      return actual is List && actual.map(s).contains(target);
    case 'does not include':
      return !(actual is List && actual.map(s).contains(target));
    case 'has file':
      return actual is List ? actual.isNotEmpty : actual != null;
    case 'no file':
      return actual is List ? actual.isEmpty : actual == null;
    case 'has photo':
    case 'has signature':
      return _hasMediaItems(actual);
    case 'no photo':
    case 'no signature':
      return !_hasMediaItems(actual);
    case 'answer is':
      return actual == target;
    default:
      return false;
  }
}

/// Full per-field visibility/required computation, keyed by component id.
Map<String, FieldState> computeFieldStates(
  InspectionSchema schema,
  Map<String, dynamic> answers,
) {
  final states = <String, FieldState>{};

  for (final field in schema.components) {
    final hasShowRule = schema.conditionalRules.any(
      (r) => r.enabled && r.actionEnabled && r.actionType == 'show' && r.actionFieldId == field.id,
    );
    states[field.id] = FieldState(visible: !hasShowRule, required: field.required);
  }

  for (final rule in schema.conditionalRules) {
    if (!rule.enabled) continue;
    if (rule.conditionFieldId.isEmpty || rule.operatorName.isEmpty) continue;
    if (rule.actionType == 'email_admin' || !rule.actionEnabled) continue;
    final targetId = rule.actionFieldId;
    if (targetId == null || targetId.isEmpty) continue;
    final target = states[targetId];
    if (target == null) continue;

    if (evaluateCondition(rule, schema, answers)) {
      switch (rule.actionType) {
        case 'show':
          target.visible = true;
        case 'hide':
          target.visible = false;
        case 'require':
          target.required = true;
        case 'unrequire':
          target.required = false;
      }
    }
  }

  return states;
}

/// The filtered, required-patched list the form screen renders — recompute
/// on every answer change (cheap: schemas are small, and this mirrors the
/// web's own `useMemo` which reruns on every `formData` change too).
List<InspectionField> visibleFieldsFor(InspectionSchema schema, Map<String, dynamic> answers) {
  final states = computeFieldStates(schema, answers);
  return [
    for (final field in schema.components)
      if (states[field.id]!.visible) field.copyWithRequired(states[field.id]!.required),
  ];
}
