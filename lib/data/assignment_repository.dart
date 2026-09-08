import '../core/offline/sync_client.dart';
import '../domain/maintenance_record.dart';

class AssignmentRepository {
  AssignmentRepository(this._sync);

  final SyncClient _sync;

  /// Accept or decline an invite. The responding technician is taken from the
  /// verified token server-side, never from this body. Queues offline like any
  /// other mutation, so a reply given in the field is not lost.
  Future<SyncedWrite> respond(
    OrderType type,
    String id, {
    required bool accept,
    String? reason,
  }) => _sync.syncRequest(
    'post',
    '/api/fm/${type.entityPath}/$id/assignment/respond',
    data: {
      'action': accept ? 'accept' : 'decline',
      if (!accept) 'reason': reason,
    },
    label: accept ? 'Accept assignment' : 'Decline assignment',
    entityType: type.name,
    entityId: id,
  );
}
