import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/inspection/conditional_logic.dart';
import '../core/offline/sync_client.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection.dart';
import 'providers.dart';

final inspectionRepositoryProvider = Provider<InspectionRepository>(
  (ref) => InspectionRepository(ref.watch(syncClientProvider)),
);

/// The assigned-inspections list. A queued submission flushing (or being
/// dropped as a conflict) moves an assignment from pending to completed
/// without this provider knowing, so it refetches on every queue change —
/// same reasoning as `OrderDetailController`.
final assignedInspectionsProvider =
    FutureProvider<List<InspectionAssignmentSummary>>((ref) async {
      ref.watch(queueChangedProvider);
      return ref.read(inspectionRepositoryProvider).listAssigned();
    });

class InspectionDetailController
    extends FamilyAsyncNotifier<InspectionAssignmentDetail, String> {
  var _disposed = false;

  @override
  Future<InspectionAssignmentDetail> build(String assignmentId) {
    ref.onDispose(() => _disposed = true);
    ref.listen(queueChangedProvider, (_, _) => refresh());
    return ref.read(inspectionRepositoryProvider).detail(assignmentId);
  }

  Future<void> refresh() async {
    final result = await AsyncValue.guard(
      () => ref.read(inspectionRepositoryProvider).detail(arg),
    );
    if (_disposed) return;
    state = result;
  }

  /// Required fields the server won't accept blank, evaluated against the
  /// same conditional show/hide/require engine the form screen renders
  /// with (`visibleFieldsFor`) — a hidden field is never required, and a
  /// field a rule has `require`d is checked even if the schema itself
  /// didn't mark it required. Server-side (`findMissingRequiredFields` in
  /// `technicianInspectionController.ts`) still uses the cruder "skip any
  /// conditional-rule target" fallback, so it stays a conservative backstop
  /// under this more accurate client check, never a stricter one.
  List<String> missingRequiredFields(Map<String, dynamic> responseData) {
    final schema = state.valueOrNull?.schema;
    if (schema == null) return const [];

    final missing = <String>[];
    for (final field in visibleFieldsFor(schema, responseData)) {
      if (!field.required) continue;
      switch (field.type) {
        case InspectionFieldType.panel:
        case InspectionFieldType.html:
        case InspectionFieldType.button:
        case InspectionFieldType.unsupported:
          // Never blockable — mirrors the web, which has no meaningful
          // "filled" state for these (a latent web bug lets `required`
          // block `html`/`panel` submission there; not worth replicating).
          continue;
        case InspectionFieldType.photo:
        case InspectionFieldType.signature:
          final value = responseData[field.key];
          final hasUploaded =
              value is Map &&
              value['values'] is List &&
              (value['values'] as List).any(
                (v) => v is Map && v['uploadStatus'] == 'uploaded',
              );
          if (!hasUploaded) missing.add(field.label);
        case InspectionFieldType.selectboxes:
          final value = responseData[field.key];
          final anyChecked = value is Map && value.values.any((v) => v == true);
          if (!anyChecked) missing.add(field.label);
        case InspectionFieldType.survey:
          final value = responseData[field.key];
          final allAnswered =
              value is Map && field.surveyRows.every((row) => value.containsKey(row.value));
          if (!allAnswered) missing.add(field.label);
        case InspectionFieldType.checkbox:
          // Web's `!formData[key]` treats an unchecked `false` as falsy —
          // match that rather than the generic null/empty-string check.
          if (responseData[field.key] != true) missing.add(field.label);
        default:
          final value = responseData[field.key];
          final isEmpty =
              value == null ||
              (value is String && value.trim().isEmpty) ||
              (value is List && value.isEmpty);
          if (isEmpty) missing.add(field.label);
      }
    }
    return missing;
  }

  /// Returns null on success (or a queued-offline outcome), the offline
  /// message when queued, or an error string when the server rejected it.
  Future<String?> submit(Map<String, dynamic> responseData) async {
    try {
      final write = await ref
          .read(inspectionRepositoryProvider)
          .submit(arg, responseData);
      await refresh();
      ref.invalidate(assignedInspectionsProvider);
      return write.synced ? null : kOfflineQueuedMessage;
    } catch (e) {
      return 'Failed to submit this inspection. Please try again.';
    }
  }
}

final inspectionDetailControllerProvider = AsyncNotifierProvider.family<
  InspectionDetailController,
  InspectionAssignmentDetail,
  String
>(InspectionDetailController.new);
