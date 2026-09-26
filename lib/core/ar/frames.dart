import 'vec.dart';

// The one place the app converts between IFC world (project coordinates) and
// the tile frame (docs/ar-bim-overlay.md §3, CONTRACT C2). Mirrors the
// server's `src/services/ar/frames.ts` function for function; both suites
// assert the same golden vectors (test/ar_frames_test.dart), so the two
// sides can't drift apart without a test failing.
//
// - **IFC world:** Z-up metres, where marker poses are stored
//   (`posProject`), because a pose in tile coordinates would break on every
//   new model build.
// - **Building-local:** IFC world re-centred by the building frame (the
//   coordination matrix of the building's first published build), still
//   Z-up.
// - **Tile frame:** building-local with one axis swap,
//   `tile(x, y, z) = (xl, zl, −yl)`. Y is up here and in AR.
//
// [frame] is always the build's `buildingFrame`, never its own
// `coordMatrix`: every build of one building is served in one frame, so
// architecture and MEP tiles line up even though web-ifc re-centres each
// model separately.

/// IFC world point → tile frame point.
Vec3 projectToTile(Vec3 p, Mat4 frame) =>
    zUpToYUp(frame.invertRigid().transformPoint(p));

/// Tile frame point → IFC world point.
Vec3 tileToProject(Vec3 p, Mat4 frame) => frame.transformPoint(yUpToZUp(p));

/// IFC world direction (a wall normal, a board's up) → tile frame. Rotation
/// only: a direction has no position, so the translation must not apply.
Vec3 dirProjectToTile(Vec3 d, Mat4 frame) =>
    zUpToYUp(frame.invertRigid().transformDir(d));

/// Tile frame direction → IFC world.
Vec3 dirTileToProject(Vec3 d, Mat4 frame) => frame.transformDir(yUpToZUp(d));

/// Building-local Z-up → tile Y-up: `(x, y, z) → (x, z, −y)`. Applied exactly
/// once on the way in; nothing downstream ever sees Z-up.
Vec3 zUpToYUp(Vec3 local) => Vec3(local.x, local.z, -local.y);

/// Tile Y-up → building-local Z-up, the inverse of [zUpToYUp]:
/// `(x, y, z) → (x, −z, y)`.
Vec3 yUpToZUp(Vec3 tile) => Vec3(tile.x, -tile.z, tile.y);
