import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/offline/offline_db.dart';
import '../core/offline/queue_bus.dart';
import '../core/offline/sync_client.dart';
import '../core/storage/secure_store.dart';
import '../core/storage/session_store.dart';
import '../core/c2o/c2o_asset_resolver.dart';
import '../core/c2o/route_download_service.dart';
import '../core/floorplan/floor_plan_image_cache.dart';
import '../data/asset_repository.dart';
import '../data/asset_tag_issue_repository.dart';
import '../data/auth_repository.dart';
import '../data/c2o_field_verification_repository.dart';
import '../data/field_verification_repository.dart';
import '../data/floor_plan_repository.dart';
import '../data/notifications_repository.dart';
import '../data/route_assignment_repository.dart';
import '../data/route_pack_repository.dart';
import '../data/technician_location_repository.dart';

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

final technicianLocationRepositoryProvider = Provider<TechnicianLocationRepository>(
  (ref) => TechnicianLocationRepository(ref.watch(apiClientProvider)),
);

final c2oFieldVerificationRepositoryProvider = Provider<C2oFieldVerificationRepository>(
  (ref) => C2oFieldVerificationRepository(ref.watch(apiClientProvider)),
);

/// FR-3 — submits the capture form (result/condition/photos/GPS) built on
/// top of the read-only scan resolve above.
final fieldVerificationRepositoryProvider = Provider<FieldVerificationRepository>(
  (ref) => FieldVerificationRepository(ref.watch(syncClientProvider)),
);

final assetTagIssueRepositoryProvider = Provider<AssetTagIssueRepository>(
  (ref) => AssetTagIssueRepository(ref.watch(syncClientProvider)),
);

final assetRepositoryProvider = Provider<AssetRepository>(
  (ref) => AssetRepository(ref.watch(syncClientProvider)),
);

/// FR-2.8 — floor+pin metadata (small JSON, rides the sync cache).
final floorPlanRepositoryProvider = Provider<FloorPlanRepository>(
  (ref) => FloorPlanRepository(ref.watch(syncClientProvider)),
);

/// FR-2.8 — the plan image itself (large binary, its own on-disk cache;
/// see [FloorPlanImageCache]'s doc comment for why it is separate).
final floorPlanImageCacheProvider = Provider<FloorPlanImageCache>(
  (ref) => FloorPlanImageCache(),
);

/// FR-1.1 — offline-first resolve of a scanned c2o tag.
final c2oAssetResolverProvider = Provider<C2oAssetResolver>(
  (ref) => C2oAssetResolver(
    db: ref.watch(offlineDbProvider),
    repo: ref.watch(c2oFieldVerificationRepositoryProvider),
  ),
);

final routePackRepositoryProvider = Provider<RoutePackRepository>(
  (ref) => RoutePackRepository(ref.watch(apiClientProvider)),
);

/// FR-5.1/SR-1 — downloads a route pack and writes it into the same c2o
/// cache FR-1.1's single-scan resolve already uses.
final routeDownloadServiceProvider = Provider<RouteDownloadService>(
  (ref) => RouteDownloadService(
    fetcher: ref.watch(routePackRepositoryProvider),
    assetCache: ref.watch(offlineDbProvider),
    routeStore: ref.watch(offlineDbProvider),
  ),
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

/// Bumped by the routes screen after a download/delete completes, so
/// [downloadedRoutePacksProvider] re-reads — route packs aren't part of the
/// offline mutation queue, so [queueChangedProvider]'s tick doesn't cover them.
final routePacksTickProvider = StateProvider<int>((ref) => 0);

final downloadedRoutePacksProvider = FutureProvider<List<DownloadedRoutePack>>((ref) async {
  ref.watch(routePacksTickProvider);
  return ref.watch(offlineDbProvider).listRoutePacks();
});

final routeAssignmentRepositoryProvider = Provider<RouteAssignmentRepository>(
  (ref) => RouteAssignmentRepository(
    ref.watch(syncClientProvider),
    ref.watch(apiClientProvider),
  ),
);

/// FR-5.5 — routes an admin assigned to this technician. Not tied to
/// [routePacksTickProvider]: downloading doesn't change the assignment list,
/// and the "Downloaded" state is derived by crossing it with
/// [downloadedRoutePacksProvider] in the screen.
final assignedRoutesProvider = FutureProvider<AssignedRoutesRead>(
  (ref) => ref.watch(routeAssignmentRepositoryProvider).fetchMine(),
);

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
