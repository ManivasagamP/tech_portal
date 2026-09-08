import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/offline/offline_db.dart';
import '../core/offline/queue_bus.dart';
import '../core/offline/sync_client.dart';
import '../core/storage/secure_store.dart';
import '../core/storage/session_store.dart';
import '../data/auth_repository.dart';
import '../data/notifications_repository.dart';

/// All four are constructed in main() and injected via ProviderScope overrides.
final secureStoreProvider = Provider<SecureStore>(
  (ref) => throw UnimplementedError(),
);
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => throw UnimplementedError(),
);
final apiClientProvider = Provider<ApiClient>(
  (ref) => throw UnimplementedError(),
);
final offlineDbProvider = Provider<OfflineDb>(
  (ref) => throw UnimplementedError(),
);

final queueBusProvider = Provider<QueueBus>((ref) {
  final bus = QueueBus();
  ref.onDispose(bus.dispose);
  return bus;
});

final syncClientProvider = Provider<SyncClient>((ref) {
  final client = SyncClient(
    api: ref.watch(apiClientProvider),
    db: ref.watch(offlineDbProvider),
    bus: ref.watch(queueBusProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

/// Fires whenever the offline queue changes, so lists can correct themselves.
final queueChangedProvider = StreamProvider<int>(
  (ref) => ref.watch(queueBusProvider).stream,
);

final pendingMutationCountProvider = FutureProvider<int>((ref) async {
  ref.watch(queueChangedProvider);
  return ref.watch(offlineDbProvider).countMutations();
});

/// The full queue, oldest first — what the Sync Center list renders.
final pendingMutationsProvider = FutureProvider<List<PendingMutation>>((
  ref,
) async {
  ref.watch(queueChangedProvider);
  return ref.watch(offlineDbProvider).listMutations();
});

/// Live progress of the in-flight [SyncClient.flushQueue] run, null when idle.
/// Reuses [queueChangedProvider]'s tick rather than a stream of its own — a
/// flush already calls `QueueBus.notify()` after every item, so watching the
/// same tick and re-reading [SyncClient.progress] keeps this in step with
/// [pendingMutationsProvider] and [pendingMutationCountProvider] for free.
final syncProgressProvider = Provider<SyncProgress?>((ref) {
  ref.watch(queueChangedProvider);
  return ref.watch(syncClientProvider).progress;
});

final syncConflictsProvider = FutureProvider<List<SyncConflict>>((ref) async {
  ref.watch(queueChangedProvider);
  return ref.watch(offlineDbProvider).listConflicts();
});

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

/// Feeds the header bell. Kept separate from the notifications screen so the
/// badge can refresh without holding the whole list.
final unseenNotificationCountProvider = FutureProvider<int>((ref) async {
  try {
    final page = await ref
        .watch(notificationsRepositoryProvider)
        .list(limit: 1);
    return page.unseenCount;
  } catch (_) {
    // A badge is not worth surfacing an error for; show nothing.
    return 0;
  }
});
