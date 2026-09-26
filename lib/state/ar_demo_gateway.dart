import 'dart:async';
import 'dart:math' as math;

import '../core/ar/corner_matcher.dart';
import '../core/ar/marker_code.dart';
import '../core/ar/vec.dart';
import 'ar_engine_bridge.dart' show ArTile;
import 'ar_gateway.dart';
import 'ar_view_models.dart';

/// Demo mode's building: "Tower A · Level 3", held in memory.
///
/// Sized and named after the design canvas (Plant Room B, AHU-03, IV-12,
/// L03-M06/M07, the SP-… spare) so the screens look like the mock-ups. Codes
/// carry real check characters (7K3QX9R and 4Q2MA76 are contract goldens).
/// Writes succeed after a short, realistic delay and change only this
/// in-memory copy; nothing reaches the server.
class DemoArGateway implements ArGateway {
  DemoArGateway();

  static const buildingId = 'demo-tower-a';
  static const buildingName = 'Tower A';
  static const level3 = 'demo-level-3';
  static const level4 = 'demo-level-4';
  static const level2 = 'demo-level-2';
  static const archBuild = 'demo-arch-v7';
  static const mepBuild = 'demo-mep-v7';

  /// The board the Demo scan opens (L03-M07, a contract golden code).
  static const focusCode = '7K3QX9R';

  /// The spare the "leave a board" demo sticks up (label SP-M0R5).
  static const demoSpareCode = 'M0R5E85';

  /// The user the demo pretends someone else is (four-eyes needs two).
  static const otherUser = 'demo-rana';
  static const me = 'demo-me';

  final Map<String, ArProgressEntry> _progress = {
    'demo-gid-chw-s2': const ArProgressEntry(globalId: 'demo-gid-chw-s2', status: ArProgressStatus.installed, installedBy: otherUser),
    'demo-gid-chw-s3': const ArProgressEntry(globalId: 'demo-gid-chw-s3', status: ArProgressStatus.installed, installedBy: otherUser),
    'demo-gid-iv12': const ArProgressEntry(globalId: 'demo-gid-iv12', status: ArProgressStatus.verified, installedBy: otherUser, verifiedBy: 'demo-sam'),
    'demo-gid-duct': const ArProgressEntry(globalId: 'demo-gid-duct', status: ArProgressStatus.installed, installedBy: me),
    'demo-gid-ahu03': const ArProgressEntry(globalId: 'demo-gid-ahu03', status: ArProgressStatus.verified, installedBy: otherUser, verifiedBy: 'demo-sam'),
  };

  final List<ArMarkerInfo> _boundSpares = [];
  final Set<String> _installed = {};

  @override
  bool get isDemo => true;

  Future<void> _latency([int ms = 350]) => Future<void>.delayed(Duration(milliseconds: ms));

  // ------------------------------------------------------------- floors

  @override
  Future<List<ArFloorSummary>> floorsForBuilding(String buildingId) async {
    await _latency(250);
    final now = DateTime(2026, 9, 24);
    return [
      const ArFloorSummary(
        floorId: level2,
        name: 'Level 2',
        elevation: 6.4,
        models: [
          ArModelEntry(lineage: 'arch', modelName: 'Architecture', state: ArModelState.building, reason: 'Build in progress · about 4 min'),
          ArModelEntry(lineage: 'mep', modelName: 'MEP', state: ArModelState.noIfc, reason: 'Source IFC missing · ask your BIM manager'),
        ],
      ),
      ArFloorSummary(
        floorId: level3,
        name: 'Level 3',
        elevation: 9.6,
        models: [
          ArModelEntry(
            lineage: 'arch',
            modelName: 'Architecture',
            state: ArModelState.ready,
            buildId: archBuild,
            version: 7,
            publishedAt: now,
            bytes: 5 * 1024 * 1024,
            onDeviceBytes: 5 * 1024 * 1024,
            onDevice: true,
          ),
          ArModelEntry(
            lineage: 'mep',
            modelName: 'MEP',
            state: ArModelState.ready,
            buildId: mepBuild,
            version: 7,
            publishedAt: now,
            bytes: 9 * 1024 * 1024,
            onDeviceBytes: 9 * 1024 * 1024 - (1.2 * 1024 * 1024).round(),
            changedTiles: 3,
            updateAvailable: true,
          ),
          ArModelEntry(
            lineage: 'structure',
            modelName: 'Structure',
            state: ArModelState.ready,
            buildId: 'demo-str-v5',
            version: 5,
            publishedAt: DateTime(2026, 9, 2),
            bytes: (6.4 * 1024 * 1024).round(),
          ),
          const ArModelEntry(
            lineage: 'fire',
            modelName: 'Fire protection',
            state: ArModelState.noIfc,
            reason: 'Source IFC missing · ask your BIM manager',
          ),
        ],
        markerCount: 2,
        cornerCount: _corners.length,
        gridNames: const ['A', 'B', 'C', 'D', '1', '2', '3'],
      ),
      ArFloorSummary(
        floorId: level4,
        name: 'Level 4',
        elevation: 12.8,
        models: [
          ArModelEntry(
            lineage: 'arch',
            modelName: 'Architecture',
            state: ArModelState.ready,
            buildId: 'demo-arch-l4-v7',
            version: 7,
            publishedAt: now,
            bytes: 4 * 1024 * 1024,
          ),
        ],
        markerCount: 1,
        cornerCount: 4,
        gridNames: const ['A', 'B', '1', '2'],
      ),
    ];
  }

  @override
  Future<ArFloorContext> floorContext(String floorId, {String? focusCode}) async {
    await _latency(300);
    if (floorId == level4) {
      return ArFloorContext(
        buildingId: buildingId,
        buildingName: buildingName,
        floorId: level4,
        floorName: 'Level 4',
        builds: [ArBuildRef(buildId: 'demo-arch-l4-v7', lineage: 'arch', modelName: 'Architecture', version: 7, publishedAt: DateTime(2026, 9, 24))],
        tiles: const [],
        markers: [_marker('N4K8P2M', 'L04-M01', 'active', const Vec3(0.05, 1.5, 6), const Vec3(1, 0, 0), 'Riser lobby · west wall', floor: level4)],
        corners: _corners.take(4).toList(),
        gridLines: _grid.take(4).toList(),
        totalBytes: 4 * 1024 * 1024,
        focusBytes: 1500000,
      );
    }
    return ArFloorContext(
      buildingId: buildingId,
      buildingName: buildingName,
      floorId: level3,
      floorName: 'Level 3',
      builds: [
        ArBuildRef(buildId: archBuild, lineage: 'arch', modelName: 'Architecture', version: 7, publishedAt: DateTime(2026, 9, 24)),
        ArBuildRef(buildId: mepBuild, lineage: 'mep', modelName: 'MEP', version: 7, publishedAt: DateTime(2026, 9, 24)),
      ],
      tiles: const [],
      markers: [..._markers, ..._boundSpares],
      corners: _corners,
      gridLines: _grid,
      totalBytes: (11.5 * 1024 * 1024).round(),
      focusBytes: (3.1 * 1024 * 1024).round(),
    );
  }

  /// A believable stream: the 15 m around the user first, then the rest.
  @override
  Future<void> download(ArFloorContext floor, {void Function(ArDownloadProgress progress)? onProgress}) async {
    final focus = floor.focusBytes;
    final total = math.max(floor.totalBytes, focus);
    const steps = 14;
    for (var i = 1; i <= steps; i++) {
      await _latency(i <= 4 ? 180 : 260);
      final focusDone = i >= 4 ? focus : (focus * i / 4).round();
      final done = i <= 4 ? focusDone : focus + ((total - focus) * (i - 4) / (steps - 4)).round();
      onProgress?.call(ArDownloadProgress(
        focusDoneBytes: focusDone,
        focusTotalBytes: focus,
        doneBytes: done,
        totalBytes: total,
        done: i == steps,
      ));
    }
  }

  /// The sample floor has no tiles: Demo mode draws its own scene.
  @override
  Future<Map<String, String>> tilePaths(List<ArTile> tiles) async => const {};

  // ------------------------------------------------------------- resolve

  @override
  Future<ArResolveResult> resolveMarker(String code) async {
    await _latency(450);
    final canonical = MarkerCode.normalize(code);
    if (canonical == null) return const ArResolveFailed(code: 'NOT_A_MARKER');
    if (canonical == '7T2WN5Q') {
      return ArResolveFailed(
        code: 'RETIRED',
        nearestCode: '4Q2MA76',
        nearestLabel: 'L03-M06',
        nearestDistanceM: 4,
        retiredAt: DateTime(2026, 9, 3),
      );
    }
    if (canonical == demoSpareCode || canonical == '3JX8QAZ') {
      final bound = _boundSpares.where((m) => m.code == canonical);
      if (bound.isEmpty) return const ArResolveFailed(code: 'SPARE_UNBOUND');
    }
    if (canonical == 'N4K8P2M') {
      final l4 = await floorContext(level4);
      return ArResolved(
        marker: l4.markers.first,
        building: const ArBuildingRef(id: buildingId, name: buildingName),
        floorId: level4,
        floorName: 'Level 4',
        builds: l4.builds,
        focusBytes: l4.focusBytes,
        totalBytes: l4.totalBytes,
      );
    }
    final all = [..._markers, ..._boundSpares];
    for (final m in all) {
      if (m.code == canonical) {
        return ArResolved(
          marker: m,
          building: const ArBuildingRef(id: buildingId, name: buildingName),
          floorId: level3,
          floorName: 'Level 3',
          builds: [
            ArBuildRef(buildId: archBuild, lineage: 'arch', modelName: 'Architecture', version: 7, publishedAt: DateTime(2026, 9, 24)),
            ArBuildRef(buildId: mepBuild, lineage: 'mep', modelName: 'MEP', version: 7, publishedAt: DateTime(2026, 9, 24)),
          ],
          focusBytes: (3.1 * 1024 * 1024).round(),
          totalBytes: (11.5 * 1024 * 1024).round(),
          onDeviceBytes: (8.4 * 1024 * 1024).round(),
        );
      }
    }
    return const ArResolveFailed(code: 'UNKNOWN_CODE');
  }

  // ---------------------------------------------------------------- plan

  @override
  Future<ArPlan?> floorPlan(String floorId) async {
    await _latency(200);
    List<Vec2> rect(double x0, double z0, double x1, double z1) => [Vec2(x0, z0), Vec2(x1, z0), Vec2(x1, z1), Vec2(x0, z1)];
    List<Vec2> column(double x, double z) => rect(x - 0.3, z - 0.3, x + 0.3, z + 0.3);
    return ArPlan(
      minX: -1,
      minZ: -1,
      maxX: 31,
      maxZ: 19,
      walls: [
        const [Vec2(0, 0), Vec2(30, 0), Vec2(30, 18), Vec2(0, 18), Vec2(0, 0)],
        const [Vec2(14, 0), Vec2(14, 10)],
        const [Vec2(22, 0), Vec2(22, 10)],
        const [Vec2(0, 10), Vec2(11, 10)],
        const [Vec2(12, 10), Vec2(18, 10)],
        const [Vec2(19, 10), Vec2(25, 10)],
        const [Vec2(26, 10), Vec2(30, 10)],
        const [Vec2(0, 13), Vec2(4, 13)],
        const [Vec2(5, 13), Vec2(10, 13)],
        const [Vec2(10, 13), Vec2(16, 13), Vec2(16, 18)],
        const [Vec2(10, 13), Vec2(10, 18)],
        const [Vec2(16, 13), Vec2(22, 13)],
        const [Vec2(23, 13), Vec2(30, 13)],
      ],
      columns: [column(4, 3), column(10, 3), column(4, 7), column(10, 7), column(18, 3), column(18, 7), column(26, 3), column(26, 15)],
      doors: const [
        [Vec2(11, 10), Vec2(12, 10)],
        [Vec2(18, 10), Vec2(19, 10)],
        [Vec2(25, 10), Vec2(26, 10)],
        [Vec2(4, 13), Vec2(5, 13)],
        [Vec2(22, 13), Vec2(23, 13)],
      ],
      spaces: [
        ArPlanSpace(name: 'Plant Room B', polygon: rect(0, 0, 14, 10), labelAt: const Vec2(3.2, 9)),
        ArPlanSpace(name: 'Pump Room', polygon: rect(14, 0, 22, 10), labelAt: const Vec2(20, 8.8)),
        ArPlanSpace(name: 'Store', polygon: rect(22, 0, 30, 10), labelAt: const Vec2(26, 6)),
        ArPlanSpace(name: 'Corridor', polygon: rect(0, 10, 30, 13), labelAt: const Vec2(7, 11.6)),
        ArPlanSpace(name: 'Electrical', polygon: rect(0, 13, 10, 18), labelAt: const Vec2(5, 15.6)),
        ArPlanSpace(name: 'Stair', polygon: rect(10, 13, 16, 18), labelAt: const Vec2(13, 15.6)),
        ArPlanSpace(name: 'Workshop', polygon: rect(16, 13, 30, 18), labelAt: const Vec2(21, 15.6)),
      ],
      equipment: [
        ArPlanEquipment(name: 'AHU-03', polygon: rect(6, 4.5, 8.5, 6), assetId: 'demo-asset-ahu03', globalId: 'demo-gid-ahu03'),
        ArPlanEquipment(name: 'P-01', polygon: rect(15.5, 2, 16.5, 3)),
        ArPlanEquipment(name: 'P-02', polygon: rect(15.5, 5, 16.5, 6)),
      ],
    );
  }

  // ------------------------------------------------------------ features

  @override
  Future<List<ArFeature>> features(ArFloorContext floor, {Set<String>? tileHashes}) async {
    await _latency(250);
    if (floor.floorId != level3) return const [];
    return _features;
  }

  // ------------------------------------------------------------ progress

  @override
  Future<ArProgressSnapshot> progress(String floorId) async {
    await _latency(300);
    return _snapshot();
  }

  ArProgressSnapshot _snapshot() {
    var installed = 0, verified = 0, issue = 0;
    for (final e in _progress.values) {
      switch (e.status) {
        case ArProgressStatus.installed:
          installed++;
        case ArProgressStatus.verified:
          verified++;
        case ArProgressStatus.issue:
          issue++;
        case ArProgressStatus.notStarted:
          break;
      }
    }
    return ArProgressSnapshot(
      entries: Map.of(_progress),
      total: _features.length,
      installed: installed,
      verified: verified,
      issue: issue,
    );
  }

  /// Four-eyes, like the server: "verified" needs a prior "installed" by
  /// someone else.
  @override
  Future<ArProgressWriteResult> setProgress({
    required String floorId,
    required List<String> globalIds,
    required ArProgressStatus status,
    String? note,
  }) async {
    await _latency(400);
    final rejected = <ArProgressRejection>[];
    var updated = 0;
    for (final id in globalIds) {
      final prev = _progress[id];
      if (status == ArProgressStatus.verified) {
        if (prev == null || (prev.status != ArProgressStatus.installed && prev.status != ArProgressStatus.verified)) {
          rejected.add(ArProgressRejection(globalId: id, reason: 'NOT_INSTALLED'));
          continue;
        }
        if (prev.installedBy == me) {
          rejected.add(ArProgressRejection(globalId: id, reason: 'SECOND_PERSON_REQUIRED'));
          continue;
        }
      }
      _progress[id] = ArProgressEntry(
        globalId: id,
        status: status,
        installedBy: status == ArProgressStatus.installed ? me : prev?.installedBy,
        installedAt: status == ArProgressStatus.installed ? DateTime.now() : prev?.installedAt,
        verifiedBy: status == ArProgressStatus.verified ? me : prev?.verifiedBy,
        verifiedAt: status == ArProgressStatus.verified ? DateTime.now() : prev?.verifiedAt,
        note: note ?? prev?.note,
      );
      updated++;
    }
    return ArProgressWriteResult(updated: updated, rejected: rejected);
  }

  // -------------------------------------------------------------- writes

  @override
  Future<ArWriteResult> bindSpare({
    required String code,
    required String floorId,
    required String buildId,
    required Vec3 posTile,
    required Vec3 normalTile,
    String? label,
    double? sigmaM,
  }) async {
    await _latency(600);
    if (_boundSpares.any((m) => m.code == code)) {
      return const ArWriteResult(errorCode: 'ALREADY_BOUND', message: 'Already bound');
    }
    final marker = ArMarkerInfo(
      code: code,
      label: (label == null || label.isEmpty) ? 'L03-M13' : label,
      status: 'installed',
      accuracyClass: 'derived',
      posTile: posTile,
      normalTile: normalTile,
      sigmaM: sigmaM,
      floorId: floorId,
    );
    _boundSpares.add(marker);
    return ArWriteResult(synced: true, marker: marker);
  }

  @override
  Future<ArWriteResult> confirmInstall({
    required String code,
    required String buildId,
    required ArInstallChecks checks,
    Vec3? posTile,
    Vec3? normalTile,
    String? photoPath,
  }) async {
    await _latency(500);
    _installed.add(code);
    ArMarkerInfo? m;
    for (final x in _markers) {
      if (x.code == code) m = x;
    }
    return ArWriteResult(synced: true, marker: m);
  }

  @override
  Future<void> postAlignmentEvents(List<ArAlignmentReport> reports) async {}

  /// Boards the demo installer has confirmed this run.
  bool isInstalled(String code) => _installed.contains(code);

  // ---------------------------------------------------------------- data

  static ArMarkerInfo _marker(
    String code,
    String label,
    String status,
    Vec3 pos,
    Vec3 normal,
    String where, {
    String accuracy = 'feature',
    String floor = level3,
    String? note,
  }) => ArMarkerInfo(
    code: code,
    label: label,
    status: status,
    accuracyClass: accuracy,
    posTile: pos,
    normalTile: normal,
    floorId: floor,
    locationText: where,
    heightAboveFloorM: pos.y,
    installNote: note,
  );

  static final List<ArMarkerInfo> _markers = [
    _marker('4Q2MA76', 'L03-M06', 'active', const Vec3(0.05, 1.5, 5), const Vec3(1, 0, 0), 'Plant Room B · west wall'),
    _marker('7K3QX9R', 'L03-M07', 'active', const Vec3(13.95, 1.5, 5), const Vec3(-1, 0, 0), 'Plant Room B · east wall'),
    _marker('8H2KD4B', 'L03-M08', 'installed', const Vec3(18, 1.5, 0.05), const Vec3(0, 0, 1), 'Pump Room · north wall'),
    _marker('9W3TB2V', 'L03-M09', 'printed', const Vec3(20, 1.5, 9.95), const Vec3(0, 0, -1), 'Pump Room · south wall',
        note: 'Just right of the P-02 isolator'),
    _marker('5C7NP1G', 'L03-M10', 'printed', const Vec3(29.95, 1.5, 5), const Vec3(-1, 0, 0), 'Store · east wall'),
    _marker('2F6RJ8F', 'L03-M11', 'printed', const Vec3(13, 1.5, 13.05), const Vec3(0, 0, -1), 'Stair · north wall'),
    _marker('6D4XG3X', 'L03-M12', 'planned', const Vec3(0.05, 1.5, 15.5), const Vec3(1, 0, 0), 'Electrical · west wall'),
    _marker(demoSpareCode, MarkerCode.spareLabel(demoSpareCode), 'spare', Vec3.zero, const Vec3(1, 0, 0), '', accuracy: 'derived'),
  ];

  static CornerCandidate _c(
    String id,
    double x,
    double z,
    Vec2 a,
    Vec2 b,
    String kind,
    double rank,
    String label, {
    bool structural = true,
  }) => CornerCandidate(
    id: id,
    posTile: Vec3(x, 0, z),
    faceA: a,
    faceB: b,
    angleDeg: 90,
    kind: kind,
    structural: structural,
    rank: rank,
    label: label,
  );

  static final List<CornerCandidate> _corners = [
    _c('demo-c1', 4.3, 3.3, const Vec2(1, 0), const Vec2(0, 1), 'column', 0.95, 'Plant Room B · column A-1'),
    _c('demo-c2', 9.7, 3.3, const Vec2(-1, 0), const Vec2(0, 1), 'column', 0.93, 'Plant Room B · column B-1'),
    _c('demo-c3', 4.3, 6.7, const Vec2(1, 0), const Vec2(0, -1), 'column', 0.9, 'Plant Room B · column A-2'),
    _c('demo-c4', 9.7, 6.7, const Vec2(-1, 0), const Vec2(0, -1), 'column', 0.92, 'Plant Room B · column B-2'),
    _c('demo-c5', 0, 0, const Vec2(1, 0), const Vec2(0, 1), 'inside', 0.8, 'Plant Room B · north-west corner'),
    _c('demo-c6', 14, 10, const Vec2(-1, 0), const Vec2(0, -1), 'inside', 0.7, 'Plant Room B · corner by the door', structural: false),
    _c('demo-c7', 14, 0, const Vec2(-1, 0), const Vec2(0, 1), 'inside', 0.6, 'Plant Room B · north-east corner', structural: false),
    _c('demo-c8', 0, 10, const Vec2(1, 0), const Vec2(0, -1), 'inside', 0.75, 'Plant Room B · south-west corner'),
    _c('demo-c9', 18.3, 3.3, const Vec2(1, 0), const Vec2(0, 1), 'column', 0.9, 'Pump Room · column C-1'),
    _c('demo-c10', 22, 0, const Vec2(-1, 0), const Vec2(0, 1), 'inside', 0.55, 'Pump Room · north-east corner', structural: false),
    _c('demo-c11', 25.7, 3.3, const Vec2(-1, 0), const Vec2(0, 1), 'column', 0.85, 'Store · column D-1'),
    _c('demo-c12', 16, 13, const Vec2(1, 0), const Vec2(0, -1), 'outside', 0.88, 'Corridor · stair core corner'),
  ];

  static const List<ArGridLine> _grid = [
    ArGridLine(name: 'A', p0: Vec2(4, -1), p1: Vec2(4, 19)),
    ArGridLine(name: 'B', p0: Vec2(10, -1), p1: Vec2(10, 19)),
    ArGridLine(name: 'C', p0: Vec2(18, -1), p1: Vec2(18, 19)),
    ArGridLine(name: 'D', p0: Vec2(26, -1), p1: Vec2(26, 19)),
    ArGridLine(name: '1', p0: Vec2(-1, 3), p1: Vec2(31, 3)),
    ArGridLine(name: '2', p0: Vec2(-1, 7), p1: Vec2(31, 7)),
    ArGridLine(name: '3', p0: Vec2(-1, 15), p1: Vec2(31, 15)),
  ];

  static ArFeature _f(
    int id,
    String gid,
    String name,
    String type,
    Vec3 min,
    Vec3 max, {
    String discipline = 'mep',
    String? system,
    String? systemName,
    String? assetId,
    String build = mepBuild,
  }) => ArFeature(
    buildId: build,
    featureId: id,
    globalId: gid,
    name: name,
    ifcType: type,
    discipline: discipline,
    bboxMin: min,
    bboxMax: max,
    systemGlobalId: system,
    systemName: systemName,
    assetId: assetId,
    floorId: level3,
  );

  static final List<ArFeature> _features = [
    _f(0, 'demo-gid-ahu03', 'AHU-03', 'IfcUnitaryEquipment', const Vec3(6, 0, 4.5), const Vec3(8.5, 2.2, 6),
        assetId: 'demo-asset-ahu03', system: 'sys-sa', systemName: 'AHU-03 supply air'),
    _f(1, 'demo-gid-iv12', 'IV-12 isolator', 'IfcValve', const Vec3(12.2, 1.2, 8.8), const Vec3(12.5, 1.5, 9.1),
        system: 'sys-chws', systemName: 'CHW supply', assetId: 'demo-asset-iv12'),
    _f(2, 'demo-gid-chw-s1', 'CHW supply', 'IfcPipeSegment', const Vec3(1, 2.6, 8.5), const Vec3(13, 2.8, 8.7),
        system: 'sys-chws', systemName: 'CHW supply'),
    _f(3, 'demo-gid-chw-s2', 'CHW supply', 'IfcPipeSegment', const Vec3(13, 2.6, 1), const Vec3(13.2, 2.8, 8.7),
        system: 'sys-chws', systemName: 'CHW supply'),
    _f(4, 'demo-gid-chw-s3', 'CHW supply', 'IfcPipeSegment', const Vec3(8.5, 2.6, 5), const Vec3(13, 2.8, 5.2),
        system: 'sys-chws', systemName: 'CHW supply'),
    _f(5, 'demo-gid-chw-r1', 'CHW return', 'IfcPipeSegment', const Vec3(1, 2.9, 9), const Vec3(13, 3.1, 9.2),
        system: 'sys-chwr', systemName: 'CHW return'),
    _f(6, 'demo-gid-iv13', 'IV-13 isolation valve', 'IfcValve', const Vec3(12.6, 2.9, 9), const Vec3(12.8, 3.1, 9.2),
        system: 'sys-chws', systemName: 'CHW supply'),
    _f(7, 'demo-gid-duct', 'Supply air duct', 'IfcDuctSegment', const Vec3(2, 3.1, 3), const Vec3(12, 3.5, 3.6),
        system: 'sys-sa', systemName: 'AHU-03 supply air'),
    _f(8, 'demo-gid-tray', 'Cable tray', 'IfcCableCarrierSegment', const Vec3(0.5, 2.4, 0.4), const Vec3(13.5, 2.5, 0.7),
        discipline: 'electrical'),
    _f(9, 'demo-gid-p01', 'P-01 pump', 'IfcPump', const Vec3(15.5, 0, 2), const Vec3(16.5, 0.8, 3),
        system: 'sys-chws', systemName: 'CHW supply', assetId: 'demo-asset-p01'),
    _f(10, 'demo-gid-p02', 'P-02 pump', 'IfcPump', const Vec3(15.5, 0, 5), const Vec3(16.5, 0.8, 6),
        system: 'sys-chws', systemName: 'CHW supply', assetId: 'demo-asset-p02'),
    _f(11, 'demo-gid-p02-iso', 'P-02 isolator', 'IfcValve', const Vec3(19.4, 1.1, 9.6), const Vec3(19.7, 1.4, 9.9),
        system: 'sys-chws', systemName: 'CHW supply'),
  ];

  /// Features the demo scene draws, in paint order, for tap-to-pick.
  static List<ArFeature> get demoFeatures => _features;
}
