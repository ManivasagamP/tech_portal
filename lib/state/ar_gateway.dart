import '../core/ar/vec.dart';
import 'ar_engine_bridge.dart' show ArTile;
import 'ar_view_models.dart';

/// Everything the AR screens ask of the outside world, as one seam.
///
/// Two implementations: `LiveArGateway` (the real `ArRepository`, offline
/// queue and tile store) and `DemoArGateway` (a sample "Tower A · Level 3"
/// held in memory, so Demo mode can walk every flow with no server, no
/// model and no native AR). The screens never know which one they have,
/// which is also what makes them testable with a hand-written fake, like
/// every other seam in this repo.
abstract interface class ArGateway {
  /// True for the sample data. Screens show the Demo banner from this.
  bool get isDemo;

  /// `GET /buildings/:buildingId/floors`: the models picker.
  Future<List<ArFloorSummary>> floorsForBuilding(String buildingId);

  /// The floor's manifest, mapped. [focusCode] lists the tiles within 15 m
  /// of that board first. Served from the local pack when offline.
  Future<ArFloorContext> floorContext(String floorId, {String? focusCode});

  /// Downloads what is missing, focus tiles first. Completes when every tile
  /// is local; [onProgress] fires as bytes arrive.
  Future<void> download(ArFloorContext floor, {void Function(ArDownloadProgress progress)? onProgress});

  /// Local file paths (`<appSupport>/ar/tiles/<hash>.glb`) for those of
  /// [tiles] that are on this phone, by hash. Missing tiles are left out, so
  /// the engine is only ever asked to load files that exist.
  Future<Map<String, String>> tilePaths(List<ArTile> tiles);

  /// `GET /markers/resolve/:code`, from the downloaded pack first.
  Future<ArResolveResult> resolveMarker(String code);

  /// `GET /floors/:floorId/plan`, for the mini plan. Null when unavailable.
  Future<ArPlan?> floorPlan(String floorId);

  /// Feature rows for the floor's builds (optionally only some tiles).
  Future<List<ArFeature>> features(ArFloorContext floor, {Set<String>? tileHashes});

  /// `GET /progress?floorId=`.
  Future<ArProgressSnapshot> progress(String floorId);

  /// `POST /progress`. Offline-queued.
  Future<ArProgressWriteResult> setProgress({
    required String floorId,
    required List<String> globalIds,
    required ArProgressStatus status,
    String? note,
  });

  /// `POST /spares/:code/bind`. Offline-queued.
  Future<ArWriteResult> bindSpare({
    required String code,
    required String floorId,
    required String buildId,
    required Vec3 posTile,
    required Vec3 normalTile,
    String? label,
    double? sigmaM,
  });

  /// `POST /markers/:code/confirm-install`. Offline-queued; the photo rides
  /// as a queued attachment.
  Future<ArWriteResult> confirmInstall({
    required String code,
    required String buildId,
    required ArInstallChecks checks,
    Vec3? posTile,
    Vec3? normalTile,
    String? photoPath,
  });

  /// `POST /alignment-events`. Offline-queued, fire and forget.
  Future<void> postAlignmentEvents(List<ArAlignmentReport> reports);
}
