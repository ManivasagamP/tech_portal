import '../../domain/maintenance_record.dart';
import 'offline_db.dart';

/// Turns a [PendingMutation]'s stored `entityType`/`entityId` back into an
/// [OrderType] and a display line, for the Sync Center list and the Home
/// screen's progress card. A mutation enqueued before entity tracking
/// existed carries neither, so every accessor here is nullable rather than
/// falling back to a guess.
extension MutationEntity on PendingMutation {
  OrderType? get orderType {
    final stored = entityType;
    if (stored == null) return null;
    for (final value in OrderType.values) {
      if (value.name == stored) return value;
    }
    return null;
  }

  /// "Work Order · 7c1e94a2" — the closest thing to a human title available
  /// without a network round trip, since the record itself may not be
  /// cached on this device. Null when this mutation can't be tied to an
  /// order (predates entity tracking, or the type no longer matches).
  String? get orderReference {
    final type = orderType;
    final id = entityId;
    if (type == null || id == null || id.isEmpty) return null;
    final short = id.length > 8 ? id.substring(0, 8) : id;
    return '${type.label} · $short';
  }

  /// Groups mutations for the same order together in the Sync Center list.
  /// Falls back to the mutation's own id — effectively its own group of one
  /// — for a write with no resolvable order, so it still renders instead of
  /// being silently dropped from the list.
  String get groupKey {
    final type = entityType;
    final id = entityId;
    return type != null && id != null ? '$type:$id' : clientMutationId;
  }
}
