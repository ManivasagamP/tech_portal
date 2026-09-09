import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../data/close_repository.dart';
import '../domain/downtime.dart';
import '../domain/maintenance_record.dart';
import 'providers.dart';

/// Everything the three close calls need, gathered by the sheet.
class CloseRequest {
  const CloseRequest({
    required this.type,
    required this.recordId,
    required this.impact,
    this.rootCause,
    this.rcaNotes,
    this.downtimeStart,
    this.downtimeEnd,
    this.hasAsset = false,
    this.hasOpenWindow = false,
    this.manualHours,
  });

  final OrderType type;
  final String recordId;
  final String? rootCause;
  final String? rcaNotes;
  final DateTime? downtimeStart;
  final DateTime? downtimeEnd;
  final DowntimeImpact impact;

  /// No linked asset means no downtime to record — the server falls back to the
  /// record's own dates for reporting.
  final bool hasAsset;

  /// A window is already running on this record, so an end time is compulsory:
  /// it is what closes the window.
  final bool hasOpenWindow;
  final double? manualHours;
}

sealed class CloseResult {
  const CloseResult();
}

/// The record is closed. [queued] means the calls are sitting in the offline
/// queue and will replay, in order, on reconnect.
class CloseSucceeded extends CloseResult {
  const CloseSucceeded({required this.queued});
  final bool queued;
}

/// The server says it was already completed — an earlier sync, or another
/// device, got there first. The end state the technician wanted is true, so
/// this is a success and not something to retry.
class CloseAlreadyClosed extends CloseResult {
  const CloseAlreadyClosed();
}

/// A 422 close gate. [missing] is the server's own list, never re-derived here.
class CloseRejected extends CloseResult {
  const CloseRejected({required this.missing, required this.message});
  final List<String> missing;
  final String message;

  bool get needsRootCause => missing.contains('rootCause');
  bool get needsChecklist => missing.contains('checklist');

  /// The unconditional signature gate (2026-09-09) — see
  /// `checklistCloseGuard.ts` (server). Reachable in normal use only if the
  /// signature write above got queued offline and has not synced yet by the
  /// time the completion call reaches the server.
  bool get needsSignature => missing.contains('signature');
}

/// Something the technician has to fix before the calls are worth sending, or
/// a failure with nothing structured to say.
class CloseFailed extends CloseResult {
  const CloseFailed(this.message);
  final String message;
}

/// Runs the close as the server expects it: root cause, then downtime, then the
/// completion call — in that order, each through the offline queue. The queue
/// replays oldest-first and stops at the first network failure, so a close made
/// with no signal lands as the same three calls once the phone reconnects.
///
/// One instance per open sheet: it remembers which steps already landed so a
/// retry after a rejected completion does not rewrite them.
class CloseSubmitter {
  CloseSubmitter(this._repository);

  final CloseRepository _repository;

  /// Downtime is written once per sheet. Without this, a 422 on the completion
  /// call followed by a retry would send the same PATCH again.
  bool _downtimeHandled = false;

  Future<CloseResult> submit(CloseRequest request) async {
    var queued = false;

    try {
      // Step 1 — root cause. Sent before the close so the server's re-check of
      // the stored row in step 3 already sees it. Re-sending on a retry is
      // harmless: the write overwrites with the same values.
      final rootCause = request.rootCause;
      final rcaNotes = request.rcaNotes;
      if ((rootCause != null && rootCause.isNotEmpty) ||
          (rcaNotes != null && rcaNotes.isNotEmpty)) {
        final write = await _repository.submitRca(
          request.type,
          request.recordId,
          rootCause: rootCause,
          rcaNotes: rcaNotes,
        );
        queued = queued || !write.synced;
      }

      // Step 2 — downtime.
      if (!_downtimeHandled && request.hasAsset) {
        final start = request.downtimeStart;
        final end = request.downtimeEnd;

        if (request.hasOpenWindow && end == null) {
          return const CloseFailed(
            'Enter the time the asset started running again to close the open '
            'downtime window.',
          );
        }
        if ((start != null || end != null) && (start == null || end == null)) {
          return const CloseFailed(
            'Enter both a start and an end time, or clear both to skip '
            'recording downtime for this close.',
          );
        }
        if (start != null && end != null) {
          final write = await _repository.patchDowntime(
            request.type,
            request.recordId,
            startedAt: start,
            endedAt: end,
            impact: request.impact,
          );
          queued = queued || !write.synced;
        }
        _downtimeHandled = true;
      }

      // Step 3 — the call that closes the record.
      try {
        final write = await _repository.complete(
          request.type,
          request.recordId,
          actualHours: request.manualHours,
          rootCause: rootCause,
        );
        queued = queued || !write.synced;
      } on HttpFailure catch (e) {
        // A 5xx here is not proof of failure. The work-order controller
        // commits the completion and then throws on a line referencing an
        // undefined `status`, so the record closes and the technician is told
        // it did not. Ask the server what actually happened before reporting
        // an error; only a record that is still open is a real failure.
        if (e.status < 500 || !await _repository.isCompleted(
              request.type,
              request.recordId,
            )) {
          rethrow;
        }
      }

      return CloseSucceeded(queued: queued);
    } on HttpFailure catch (e) {
      if (e.isAlreadyCompleted) return const CloseAlreadyClosed();
      if (e.status == 422 && e.missing.isNotEmpty) {
        return CloseRejected(
          missing: e.missing,
          message: e.message.isEmpty
              ? 'This job cannot be closed yet.'
              : e.message,
        );
      }
      return CloseFailed(
        e.message.isEmpty ? 'Failed to close this job.' : e.message,
      );
    } catch (_) {
      return const CloseFailed('Failed to close this job.');
    }
  }
}

final closeRepositoryProvider = Provider<CloseRepository>(
  (ref) => CloseRepository(
    ref.watch(apiClientProvider),
    ref.watch(syncClientProvider),
  ),
);

/// The asset's recorded downtime windows, used to pre-fill the sheet. Keyed by
/// asset id and thrown away with the sheet — a cached window would pre-fill a
/// start time that has since been closed.
final downtimeHistoryProvider =
    FutureProvider.autoDispose.family<List<DowntimeWindow>, String>(
  (ref, assetId) => ref.watch(closeRepositoryProvider).downtimeHistory(assetId),
);
