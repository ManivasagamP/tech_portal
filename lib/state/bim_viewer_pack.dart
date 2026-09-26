import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ar_repository.dart' as repo;
import '../domain/ar_models.dart' as wire;
import 'ar_catalog_controller.dart' show arGatewayProvider;
import 'ar_engine_bridge.dart' show ArTile;
import 'ar_gateway_live.dart' show ArDownloadStopped;
import 'ar_view_models.dart' show ArDownloadProgress;
import 'providers.dart';

/// The one thing the model viewer needs beyond [ArGateway]: the floor's
/// `architecture_solid` tiles (shaded walls), which the AR floor pack
/// deliberately leaves out (docs/bim-viewer.md §3). Everything else — the
/// floor pack, tile files, plan, features, Demo — comes from the AR gateway,
/// so a floor downloaded once works in AR and in the viewer.
abstract interface class BimViewerPack {
  /// The floor's solid-wall tiles; empty when the server has none (a build
  /// from before the layer, a database without the enum value) or when
  /// offline with nothing stored. Never throws for those.
  Future<List<ArTile>> solidTiles(String floorId);

  /// Downloads whichever of [solidTiles]' tiles aren't on the phone.
  Future<void> download(String floorId, {void Function(ArDownloadProgress progress)? onProgress});
}

class LiveBimViewerPack implements BimViewerPack {
  LiveBimViewerPack(this._repository);
  final repo.ArRepository _repository;
  final _manifests = <String, wire.Manifest>{};

  @override
  Future<List<ArTile>> solidTiles(String floorId) async {
    try {
      final m = await _repository.fetchViewerManifest(floorId);
      if (m == null) return const [];
      _manifests[floorId] = m;
      return [for (final t in m.tiles) if (t.layer == repo.ArRepository.solidArchitectureLayer) t];
    } catch (_) {
      return const []; // the viewer falls back to walls from the plan
    }
  }

  @override
  Future<void> download(String floorId, {void Function(ArDownloadProgress progress)? onProgress}) async {
    final m = _manifests[floorId] ?? await _repository.fetchViewerManifest(floorId);
    if (m == null || m.tiles.isEmpty) return;
    _manifests[floorId] = m;
    final result = await _repository.downloadTiles(
      m,
      onProgress: (p) => onProgress?.call(ArDownloadProgress(doneBytes: p.bytesDone, totalBytes: p.bytesTotal)),
    );
    if (!result.complete) throw ArDownloadStopped(interrupted: result.interrupted);
  }
}

/// Demo mode: no server, no tiles — the viewer draws walls from the demo
/// plan (plan massing).
class DemoBimViewerPack implements BimViewerPack {
  const DemoBimViewerPack();

  @override
  Future<List<ArTile>> solidTiles(String floorId) async => const [];

  @override
  Future<void> download(String floorId, {void Function(ArDownloadProgress progress)? onProgress}) async {}
}

final bimViewerPackProvider = Provider<BimViewerPack>((ref) {
  if (ref.watch(arGatewayProvider).isDemo) return const DemoBimViewerPack();
  return LiveBimViewerPack(ref.watch(arRepositoryProvider));
});
