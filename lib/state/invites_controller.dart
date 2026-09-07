import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../domain/maintenance_record.dart';
import 'auth_controller.dart';
import 'orders_controller.dart';
import 'order_detail_controller.dart';
import 'providers.dart';

/// The invite inbox: every kind the technician has been invited to and has not
/// answered yet. Deliberately light — four list calls, no detail loads.
class InvitesController extends AsyncNotifier<List<MaintenanceRecord>> {
  var _disposed = false;

  @override
  Future<List<MaintenanceRecord>> build() {
    ref.onDispose(() => _disposed = true);
    // A reply given offline sits in the queue; when it lands the invite is no
    // longer pending and has to leave this list.
    ref.listen(queueChangedProvider, (_, _) => refresh());
    return _load();
  }

  Future<List<MaintenanceRecord>> _load() {
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.userId.isEmpty) {
      return Future.value(const []);
    }
    return ref.read(ordersRepositoryProvider).listInvites(session.userId);
  }

  Future<void> refresh() async {
    final next = await AsyncValue.guard(_load);
    if (_disposed) return;
    state = next;
  }

  /// Answers one invite and drops it from the list. Returns a message when
  /// there is something the technician needs to be told; null on a clean
  /// accept or decline.
  Future<String?> respond(
    MaintenanceRecord record, {
    required bool accept,
    String? reason,
  }) async {
    try {
      final write = await ref.read(assignmentRepositoryProvider).respond(
            record.type,
            record.id,
            accept: accept,
            reason: reason,
          );
      await refresh();
      if (!write.synced) {
        return accept
            ? 'Accepted offline. It will be sent when you are back online.'
            : 'Declined offline. It will be sent when you are back online.';
      }
      return null;
    } on HttpFailure catch (e) {
      // The server explains refusals properly — an invite already answered, or
      // one that has moved on to the next technician in the chain.
      await refresh();
      return e.message.isEmpty ? 'That did not send. Please try again.' : e.message;
    } catch (_) {
      return 'That did not send. Please try again.';
    }
  }
}

final invitesControllerProvider =
    AsyncNotifierProvider<InvitesController, List<MaintenanceRecord>>(
  InvitesController.new,
);
