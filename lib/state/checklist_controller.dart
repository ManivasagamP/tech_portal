import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capture/capture_services.dart';
import '../core/network/api_exception.dart';
import '../core/offline/sync_client.dart';
import '../data/checklist_repository.dart';
import '../domain/checklist.dart';
import 'order_detail_controller.dart';
import 'providers.dart';

class ChecklistState {
  const ChecklistState({
    this.items = const [],
    this.busyIndex,
    this.addingOther = false,
  });

  final List<ChecklistItem> items;

  /// Which row is mid-write, so only that row shows a spinner.
  final int? busyIndex;
  final bool addingOther;

  ChecklistState copyWith({
    List<ChecklistItem>? items,
    int? busyIndex,
    bool? addingOther,
    bool clearBusy = false,
  }) => ChecklistState(
    items: items ?? this.items,
    busyIndex: clearBusy ? null : (busyIndex ?? this.busyIndex),
    addingOther: addingOther ?? this.addingOther,
  );
}

/// Result of one checklist action, as a message for the technician. Null means
/// it went straight to the server with nothing worth saying.
class ActionOutcome {
  /// The write is parked in the offline queue. Always the same one line —
  /// see [kOfflineQueuedMessage] — so every action reads as the same thing
  /// happening instead of a different notice per action type.
  const ActionOutcome.queued() : text = kOfflineQueuedMessage, queued = true;

  /// The write was refused or failed outright.
  const ActionOutcome.failed(this.text) : queued = false;

  final String text;

  /// A queued notice stops being true the moment the queue drains, so the UI
  /// clears it then. A failure notice stands until the technician dismisses it.
  final bool queued;
}

class ChecklistController extends FamilyNotifier<ChecklistState, OrderKey> {
  @override
  ChecklistState build(OrderKey arg) {
    final detail = ref.watch(orderDetailControllerProvider(arg));

    // Only server truth may replace an *existing* local list — a cached read
    // after an offline write is older than what is already on screen and
    // would undo it. But with nothing on screen yet (a cold start with no
    // prior state), that guard has nothing to protect: refusing the cached
    // list here left a job with real checklist items reading as "No
    // checklist items" the moment it was opened offline for the first time,
    // instead of showing what is actually cached.
    final incoming = detail.valueOrNull;
    if (incoming != null && (!incoming.fromCache || stateOrNull == null)) {
      return ChecklistState(items: incoming.record.checklists);
    }
    return ChecklistState(items: stateOrNull?.items ?? const []);
  }

  ChecklistRepository get _repository => ref.read(checklistRepositoryProvider);

  /// Applies the patch the server was sent to the local copy, so the row
  /// updates now rather than after a round trip.
  void _apply(int index, Map<String, dynamic> updates) {
    final items = [...state.items];
    if (index < 0 || index >= items.length) return;
    items[index] = ChecklistItem.fromJson({...items[index].raw, ...updates});
    state = state.copyWith(items: items);
  }

  Future<ActionOutcome?> _run(
    int index,
    Future<ChecklistWrite> Function(ChecklistItem item) action,
  ) async {
    if (index < 0 || index >= state.items.length) return null;
    final item = state.items[index];
    state = state.copyWith(busyIndex: index);

    try {
      final write = await action(item);
      _apply(index, write.updates);
      if (write.synced) {
        // The record carries the same checklist; without this the details tab
        // and the summary card keep the pre-write state.
        await ref.read(orderDetailControllerProvider(arg).notifier).refresh();
        return null;
      }
      return const ActionOutcome.queued();
    } on CaptureFailure catch (e) {
      return ActionOutcome.failed(e.message);
    } on HttpFailure catch (e) {
      // The server explains refusals properly — a work order still awaiting
      // supervisor acceptance, a record already closed. Repeating "try again"
      // over that would send the technician round in circles.
      return ActionOutcome.failed(
        e.message.isEmpty ? 'That did not save. Please try again.' : e.message,
      );
    } catch (_) {
      return const ActionOutcome.failed('That did not save. Please try again.');
    } finally {
      state = state.copyWith(clearBusy: true);
    }
  }

  Future<ActionOutcome?> toggle(int index) => _run(
    index,
    (item) => _repository.setCompleted(
      arg.type,
      arg.id,
      index,
      isCompleted: !item.isCompleted,
    ),
  );

  Future<ActionOutcome?> startSession(
    int index, {
    CapturedPhoto? facePhoto,
    CapturedLocation? location,
  }) => _run(
    index,
    (item) => _repository.startSession(
      arg.type,
      arg.id,
      index,
      item: item,
      facePhoto: facePhoto,
      location: location,
    ),
  );

  Future<ActionOutcome?> stopSession(
    int index, {
    CapturedPhoto? facePhoto,
    CapturedLocation? location,
  }) => _run(
    index,
    (item) => _repository.stopSession(
      arg.type,
      arg.id,
      index,
      item: item,
      facePhoto: facePhoto,
      location: location,
    ),
  );

  Future<ActionOutcome?> addNote(
    int index, {
    required String text,
    VoiceRecording? voice,
  }) => _run(
    index,
    (item) => _repository.addNote(
      arg.type,
      arg.id,
      index,
      item: item,
      text: text,
      voice: voice,
    ),
  );

  Future<ActionOutcome?> addPhoto(int index, CapturedPhoto photo) => _run(
    index,
    (item) => _repository.addAttachment(
      arg.type,
      arg.id,
      index,
      item: item,
      photo: photo,
    ),
  );

  Future<ActionOutcome?> removePhoto(int index, String url) => _run(
    index,
    (item) => _repository.removeAttachment(
      arg.type,
      arg.id,
      index,
      item: item,
      url: url,
    ),
  );

  /// The work order's own spoken note. Passing null clears it.
  Future<ActionOutcome?> setRecordVoiceNote({VoiceRecording? voice}) async {
    try {
      final write = await _repository.setRecordVoiceNote(
        arg.type,
        arg.id,
        voice: voice,
      );
      if (write.synced) {
        await ref.read(orderDetailControllerProvider(arg).notifier).refresh();
        return null;
      }
      return const ActionOutcome.queued();
    } catch (_) {
      return ActionOutcome.failed(
        voice == null
            ? 'Failed to delete the voice note.'
            : 'Failed to save the voice note.',
      );
    }
  }

  /// "Other" items go onto the record itself — the checklist endpoint can only
  /// address an index that already exists.
  Future<ActionOutcome?> addOther(String description) async {
    final record = ref
        .read(orderDetailControllerProvider(arg))
        .valueOrNull
        ?.record;
    if (record == null || description.trim().isEmpty) return null;

    state = state.copyWith(addingOther: true);
    try {
      final write = await _repository.addOtherItem(
        arg.type,
        record,
        description: description,
      );
      if (write.synced) {
        await ref.read(orderDetailControllerProvider(arg).notifier).refresh();
        return null;
      }
      return const ActionOutcome.queued();
    } on HttpFailure catch (e) {
      return ActionOutcome.failed(
        e.message.isEmpty ? 'Failed to add other task.' : e.message,
      );
    } catch (_) {
      return const ActionOutcome.failed('Failed to add other task.');
    } finally {
      state = state.copyWith(addingOther: false);
    }
  }

  /// Digital-signature sign-off (2026-09-09) — appends the drawn signature as
  /// one more checklist item via the SAME call path [addOther] above uses
  /// (`ChecklistRepository.addSignatureItem` mirrors `addOtherItem`), so it
  /// rides the offline queue exactly like every other write in this
  /// controller. See `checklistCloseGuard.ts` (server) for why the signature
  /// lives inside `checklists` instead of a new column.
  Future<ActionOutcome?> addSignature({
    required Uint8List pngBytes,
    String? signerName,
  }) async {
    final record = ref
        .read(orderDetailControllerProvider(arg))
        .valueOrNull
        ?.record;
    if (record == null) return null;

    try {
      final write = await _repository.addSignatureItem(
        arg.type,
        record,
        pngBytes: pngBytes,
        signerName: signerName,
      );
      if (write.synced) {
        await ref.read(orderDetailControllerProvider(arg).notifier).refresh();
        return null;
      }
      return const ActionOutcome.queued();
    } on HttpFailure catch (e) {
      return ActionOutcome.failed(
        e.message.isEmpty ? 'Failed to save signature.' : e.message,
      );
    } catch (_) {
      return const ActionOutcome.failed('Failed to save signature.');
    }
  }
}

final checklistRepositoryProvider = Provider<ChecklistRepository>(
  (ref) => ChecklistRepository(ref.watch(syncClientProvider)),
);

final checklistControllerProvider =
    NotifierProvider.family<ChecklistController, ChecklistState, OrderKey>(
      ChecklistController.new,
    );

final photoCaptureProvider = Provider<PhotoCapture>((ref) => PhotoCapture());
final locationCaptureProvider = Provider<LocationCapture>(
  (ref) => LocationCapture(),
);
