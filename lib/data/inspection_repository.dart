import 'dart:typed_data';

import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';
import '../domain/inspection.dart';

class InspectionRepository {
  InspectionRepository(this._sync);

  final SyncClient _sync;

  Future<List<InspectionAssignmentSummary>> listAssigned() async {
    final read = await _sync.syncGet('/api/fm/inspections/technician/assigned');
    return unwrapList(
      read.data,
    ).map(InspectionAssignmentSummary.fromJson).toList();
  }

  Future<InspectionAssignmentDetail> detail(String id) async {
    final read = await _sync.syncGet('/api/fm/inspections/technician/$id');
    return InspectionAssignmentDetail.fromJson(unwrapMap(read.data));
  }

  /// Text/number/checkbox/select/radio/date answers queue offline like every
  /// other write in this app; a technician who finishes a signal-free
  /// inspection with no photo fields can still submit it on the spot.
  Future<SyncedWrite> submit(String id, Map<String, dynamic> responseData) =>
      _sync.syncRequest(
        'post',
        '/api/fm/inspections/technician/$id/submit',
        data: {'data': responseData},
        label: 'Inspection submission',
        entityType: 'inspection',
        entityId: id,
      );

  /// Photo/signature fields upload immediately (same limitation the web
  /// FormRenderer has today — see LEARNINGS on the client repo) rather than
  /// riding `syncRequest`'s single-attachment queue slot, since one
  /// inspection can carry several media fields in one submit. Throws
  /// `NetworkFailure` offline; the form screen surfaces that as "needs a
  /// connection" for just that field, the rest of the form stays usable.
  Future<String> uploadMedia(Uint8List bytes, String fileName) =>
      _sync.uploadBytes(bytes: bytes, fileName: fileName, field: 'image');
}
