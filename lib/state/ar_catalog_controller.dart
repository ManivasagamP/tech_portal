import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/c2o/asset_detail.dart';
import 'ar_demo_gateway.dart';
import 'ar_gateway.dart';
import 'ar_gateway_live.dart';
import 'ar_prefs_controller.dart';
import 'ar_view_models.dart';
import 'providers.dart';

/// The AR screens' read side: which gateway (live or Demo), the floors of a
/// building, and how an entry point that only knows an asset or a floor
/// finds the building, floor and room it needs.

/// Live or Demo. Rebuilt when Demo mode is toggled, so every screen that
/// watches it switches data source at once.
final arGatewayProvider = Provider<ArGateway>((ref) {
  final demo = ref.watch(arPrefsProvider.select((s) => s.demo));
  if (demo) return DemoArGateway();
  return createLiveArGateway(ref);
});

/// `GET /buildings/:buildingId/floors`, with each model's on-device state.
final arFloorsProvider = FutureProvider.autoDispose.family<List<ArFloorSummary>, String>(
  (ref, buildingId) => ref.watch(arGatewayProvider).floorsForBuilding(buildingId),
);

/// Where an AR entry point lands: building, floor and (when known) the
/// target's room, so the models picker and corner A can be scoped.
class ArEntry {
  const ArEntry({
    this.buildingId,
    this.buildingName,
    this.floorId,
    this.floorName,
    this.assetId,
    this.assetName,
    this.spaceName,
    this.errorKey,
  });

  final String? buildingId;
  final String? buildingName;
  final String? floorId;
  final String? floorName;
  final String? assetId;
  final String? assetName;
  final String? spaceName;

  /// `ar.entry.*` when the entry can't be resolved (asset has no floor…).
  final String? errorKey;

  bool get resolved => buildingId != null && floorId != null;
}

typedef ArEntryArgs = ({String? buildingId, String? floorId, String? assetId});

/// Resolves an entry. From an asset: the offline C2O cache first, then the
/// asset record (both already power the asset screen), for its floor and
/// room. From a floor: the floor's manifest for its building. Demo mode
/// always lands on the sample Level 3.
final arEntryProvider = FutureProvider.autoDispose.family<ArEntry, ArEntryArgs>((ref, args) async {
  final gateway = ref.watch(arGatewayProvider);
  if (gateway.isDemo) {
    final floorId = (args.floorId == DemoArGateway.level4 || args.floorId == DemoArGateway.level2)
        ? args.floorId!
        : DemoArGateway.level3;
    return ArEntry(
      buildingId: DemoArGateway.buildingId,
      buildingName: DemoArGateway.buildingName,
      floorId: floorId,
      assetId: args.assetId == null ? null : 'demo-asset-ahu03',
      assetName: args.assetId == null ? null : 'AHU-03',
      spaceName: args.assetId == null ? null : 'Plant Room B',
    );
  }

  var floorId = args.floorId;
  String? assetName;
  String? spaceName;
  String? buildingName;
  if (args.assetId != null) {
    AssetDetail? detail;
    try {
      final cached = await ref.read(offlineDbProvider).getC2oAsset(args.assetId!);
      detail = cached == null ? null : AssetDetail.fromClaims(cached.claims);
    } catch (_) {}
    if (detail == null) {
      try {
        final page = await ref.read(assetRepositoryProvider).get(args.assetId!);
        detail = AssetDetail.fromAssetRecord(page.asset);
      } catch (_) {}
    }
    if (detail != null) {
      floorId ??= detail.floorId;
      assetName = detail.assetName ?? detail.assetReferenceId;
      for (final step in detail.locationPath) {
        final level = step.level.toLowerCase();
        if (level == 'room' || level == 'space' || level == 'area') spaceName = step.label;
        if (level == 'building') buildingName = step.label;
      }
    }
    if (floorId == null) {
      return ArEntry(assetId: args.assetId, assetName: assetName, errorKey: 'ar.entry.asset_no_floor');
    }
  }

  var buildingId = args.buildingId;
  String? floorName;
  if (floorId != null && buildingId == null) {
    try {
      final floor = await gateway.floorContext(floorId);
      buildingId = floor.buildingId;
      buildingName = floor.buildingName;
      floorName = floor.floorName;
    } catch (_) {
      return ArEntry(
        floorId: floorId,
        assetId: args.assetId,
        assetName: assetName,
        spaceName: spaceName,
        errorKey: 'ar.entry.floor_unavailable',
      );
    }
  }
  return ArEntry(
    buildingId: buildingId,
    buildingName: buildingName,
    floorId: floorId,
    floorName: floorName,
    assetId: args.assetId,
    assetName: assetName,
    spaceName: spaceName,
  );
});

/// Offline right now? Re-checked whenever the queue changes (the same
/// signal the app's offline banner uses). Demo mode is never "offline".
final arOfflineProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(queueChangedProvider);
  if (ref.watch(arGatewayProvider).isDemo) return false;
  return ref.watch(syncClientProvider).isOffline;
});

/// `GET /floors/:floorId/plan` for previews and the install run map.
final arFloorPlanProvider = FutureProvider.autoDispose.family<ArPlan?, String>(
  (ref, floorId) => ref.watch(arGatewayProvider).floorPlan(floorId),
);

/// `GET /markers/resolve/:code` for the scan sheet (M1).
final arResolveProvider = FutureProvider.autoDispose.family<ArResolveResult, String>(
  (ref, code) => ref.watch(arGatewayProvider).resolveMarker(code),
);
