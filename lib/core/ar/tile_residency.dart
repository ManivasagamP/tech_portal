import '../../domain/ar_models.dart' show ManifestTile;
import 'vec.dart';

/// What to change in the engine's resident tile set.
class ResidencyPlan {
  const ResidencyPlan({required this.load, required this.unload});

  /// Tiles to load, highest priority first (pinned, then nearest).
  final List<ManifestTile> load;

  /// Hashes to unload.
  final List<String> unload;

  bool get isEmpty => load.isEmpty && unload.isEmpty;
}

/// Which tiles should be in GPU memory right now (docs/ar-bim-overlay.md
/// §6.5): the target's tiles always, then tiles whose box is within
/// [radiusM] of the camera, nearest first, until the triangle budget is full.
///
/// **Hysteresis.** A tile already loaded stays until it is more than
/// `radiusM + hysteresisM` away, and ranks as if it were `hysteresisM`
/// closer when the budget is contended. Without that, a technician walking
/// along a cell boundary would load and unload the same tile every pose
/// (5 Hz), which costs a GLB parse each time and visibly flickers.
///
/// Pure: the session calls [plan] on each camera pose and hands the result
/// to `ArEngine.loadTiles` / `unloadTiles`.
class TileResidency {
  const TileResidency();

  ResidencyPlan plan({
    required Vec3 cameraTile,
    required List<ManifestTile> tiles,
    required Set<String> loaded,
    Set<String> pinned = const {},
    int triangleBudget = 300000,
    double radiusM = 15,
    double hysteresisM = 3,
  }) {
    final candidates = <_Ranked>[];
    for (final t in tiles) {
      final isPinned = pinned.contains(t.hash);
      final isLoaded = loaded.contains(t.hash);
      final distance = t.distanceTo(cameraTile);
      final reach = isLoaded ? radiusM + hysteresisM : radiusM;
      if (!isPinned && distance > reach) continue;
      candidates.add(_Ranked(
        tile: t,
        pinned: isPinned,
        key: isLoaded ? distance - hysteresisM : distance,
        loaded: isLoaded,
      ));
    }

    // Pinned first (the target must always be drawn), then by effective
    // distance; the hash breaks ties so the plan is deterministic.
    candidates.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final byKey = a.key.compareTo(b.key);
      return byKey != 0 ? byKey : a.tile.hash.compareTo(b.tile.hash);
    });

    final keep = <String>{};
    final load = <ManifestTile>[];
    var triangles = 0;
    for (final c in candidates) {
      if (keep.contains(c.tile.hash)) continue; // a hash listed twice
      final next = triangles + c.tile.triangleCount;
      // Pinned tiles are admitted even over budget: an overlay missing its
      // target is worse than one a little over its triangle target (the
      // hard limit is 1.5× the target, §9).
      if (!c.pinned && next > triangleBudget) continue;
      triangles = next;
      keep.add(c.tile.hash);
      if (!c.loaded) load.add(c.tile);
    }

    final unload = [
      for (final hash in loaded)
        if (!keep.contains(hash)) hash,
    ]..sort();
    return ResidencyPlan(load: load, unload: unload);
  }
}

class _Ranked {
  const _Ranked({
    required this.tile,
    required this.pinned,
    required this.key,
    required this.loaded,
  });

  final ManifestTile tile;
  final bool pinned;
  final double key;
  final bool loaded;
}
