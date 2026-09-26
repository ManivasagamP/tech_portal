/*
 * fe_ar_core: the platform-independent half of the fe_ar native engine.
 *
 * Pure C99, no dependencies beyond libc/libm, so ONE implementation serves
 * both platforms and can be compiled and unit-tested on a laptop
 * (src/test/fe_ar_core_test.c). Android reaches it over JNI
 * (android/src/main/cpp/fe_ar_jni.c), iOS compiles it straight into the pod
 * (ios/Classes/fe_ar_core_shim.c includes this file's .c, the pattern of
 * Flutter's own FFI plugin template).
 *
 * What lives here, and why it isn't in Kotlin or Swift:
 *
 *  1. A CPU copy of every resident tile's triangles, for `pick` (CONTRACT C8:
 *     "pick via ray-triangle tests against loaded tile meshes"). The tiles are
 *     EXT_meshopt_compression + KHR_mesh_quantization GLBs (CONTRACT C7).
 *     Filament's gltfio decodes them for the GPU but exposes no vertex data
 *     to Java, so the tile is decoded a second time here. The meshopt decoder
 *     is a line-by-line port of meshoptimizer's own reference decoder
 *     (meshopt_decoder_reference.js, MIT), and the test decodes buffers made
 *     by the real meshoptimizer encoder through gltf-transform, the same
 *     toolchain the server's geometry build uses.
 *  2. Corner fitting (docs/ar-setup-and-gamma-parity.md §2.3): two vertical
 *     planes from a depth point cloud (LiDAR / ARCore Depth) or from two
 *     tracked planes, intersected into a corner with its two face normals.
 *  3. Small geometry helpers the marker pipeline shares: a least-squares
 *     plane fit, and a "PnP-lite" pose of a square of known size from its
 *     four image corners (the §4.2 last-resort method).
 *  4. The overlay GLB (grid lines on the floor, snag pins, ghost boards),
 *     built as a tiny glTF so both platforms draw it with gltfio's stock
 *     unlit material and need no second custom material.
 *
 * Frames: everything here is in the frame its inputs are in. Tiles are in the
 * tile frame (CONTRACT C2: Y up, metres). Corner inputs are AR-world points
 * (Y up by gravity). Camera-space inputs follow the OpenGL/ARKit/ARCore
 * convention: +X right, +Y up, looking down -Z; image pixels have v down.
 *
 * Threading: every function is re-entrant. A parsed fe_tile is immutable and
 * may be ray-cast from any thread while another thread parses the next one.
 */
#ifndef FE_AR_CORE_H
#define FE_AR_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** A local feature index or feature id that isn't known. */
#define FE_NO_FEATURE 0xFFFFFFFFu

/* ------------------------------------------------------------------------ */
/* Tiles                                                                     */
/* ------------------------------------------------------------------------ */

typedef struct fe_tile fe_tile;

typedef struct fe_hit {
    /** Ray parameter: hit = origin + t * dir. With a unit dir, metres. */
    float t;
    /** Hit point, tile frame. */
    float point[3];
    /** Geometric normal of the hit triangle, unit, facing the ray origin. */
    float normal[3];
    /** TEXCOORD_1 local feature index of the triangle, or FE_NO_FEATURE. */
    uint32_t local_index;
    /** Triangle index inside the tile (debugging). */
    uint32_t triangle;
} fe_hit;

/**
 * Parses and decodes a GLB tile. Returns NULL on failure with a short reason
 * in err (always NUL-terminated when err_cap > 0). The input bytes are not
 * retained: the caller may free them as soon as this returns.
 *
 * Reads: every TRIANGLES primitive (mode 4) into the pick mesh; LINES
 * primitives (mode 1, the architecture layer) only into the per-feature
 * bounds (edges are never pickable); POSITION of any component type
 * (quantised or float) through the node hierarchy's transforms; TEXCOORD_1
 * as the local feature index; and extras.fe {featureIds, layer, buildId} from
 * the scene, the asset or the root (CONTRACT C7).
 */
fe_tile* fe_tile_parse(const uint8_t* glb, size_t size, char* err, size_t err_cap);
void fe_tile_free(fe_tile* tile);

uint32_t fe_tile_triangle_count(const fe_tile* tile);
uint32_t fe_tile_line_count(const fe_tile* tile);

/** Length of the extras.fe.featureIds table (0 when the tile has none). */
uint32_t fe_tile_feature_count(const fe_tile* tile);
/** The table itself (feature id per local index), or NULL. */
const int32_t* fe_tile_feature_ids(const fe_tile* tile);
/** Feature id for a local index, or -1 when unknown. */
int32_t fe_tile_feature_id(const fe_tile* tile, uint32_t local_index);
/** One past the largest local index any vertex carries (0 if none). */
uint32_t fe_tile_local_index_count(const fe_tile* tile);

/** extras.fe.layer ("mep" | "structure" | "architecture"), or "" if absent. */
const char* fe_tile_layer(const fe_tile* tile);
/** extras.fe.buildId, or "" if absent. */
const char* fe_tile_build_id(const fe_tile* tile);

/** Bounds of all geometry, tile frame. Returns 0 for an empty tile. */
int fe_tile_bounds(const fe_tile* tile, float min_out[3], float max_out[3]);
/** Bounds of one local feature index (triangles and lines). 0 if none. */
int fe_tile_local_bounds(const fe_tile* tile, uint32_t local_index, float min_out[3], float max_out[3]);

/**
 * Nearest triangle hit along origin + t * dir with 0 < t <= max_t. dir need
 * not be unit length (t is then in units of |dir|). Double-sided. Returns 1
 * and fills hit, or 0 for a miss. Brute force over triangles with a coarse
 * per-chunk bounding-box skip (docs/ar-bim-overlay.md §6.4: "brute force
 * first, a BVH only if AR-21 profiling needs one").
 */
int fe_tile_raycast(const fe_tile* tile, const float origin[3], const float dir[3], float max_t, fe_hit* hit);

/**
 * As fe_tile_raycast, but triangles whose local index l has skip[l] != 0
 * (l < skip_count) are ignored, so a feature the app has hidden through the
 * feature state is never picked and never blocks a pick behind it.
 */
int fe_tile_raycast_masked(const fe_tile* tile, const float origin[3], const float dir[3], float max_t, const uint8_t* skip,
                           uint32_t skip_count, fe_hit* hit);

/* ------------------------------------------------------------------------ */
/* meshopt decoding (exposed for tests)                                      */
/* ------------------------------------------------------------------------ */

enum {
    FE_MESHOPT_FILTER_NONE = 0,
    FE_MESHOPT_FILTER_OCTAHEDRAL = 1,
    FE_MESHOPT_FILTER_QUATERNION = 2,
    FE_MESHOPT_FILTER_EXPONENTIAL = 3,
    FE_MESHOPT_FILTER_COLOR = 4,
};

/** Vertex codec v0 (0xa0) and v1 (0xa1). 0 on success, negative on error. */
int fe_meshopt_decode_vertex(uint8_t* dst, size_t count, size_t stride, const uint8_t* src, size_t src_size);
/** Index codec v1 (0xe1), triangles; index_size 2 or 4. */
int fe_meshopt_decode_index(uint8_t* dst, size_t count, size_t index_size, const uint8_t* src, size_t src_size);
/** Index sequence codec (0xd1); index_size 2 or 4. */
int fe_meshopt_decode_sequence(uint8_t* dst, size_t count, size_t index_size, const uint8_t* src, size_t src_size);
/** In-place filter after fe_meshopt_decode_vertex. 0 on success. */
int fe_meshopt_apply_filter(uint8_t* data, size_t count, size_t stride, int filter);

/* ------------------------------------------------------------------------ */
/* Planes and corners                                                        */
/* ------------------------------------------------------------------------ */

/**
 * Least-squares plane through n points (xyz triples). Fills the centroid, the
 * unit normal (sign arbitrary) and the RMS point-to-plane distance.
 * Returns 0 with fewer than 3 points or a degenerate set.
 */
int fe_fit_plane(const float* xyz, size_t n, float centroid[3], float normal[3], float* rms);

typedef enum fe_corner_kind {
    FE_CORNER_INSIDE = 0,
    FE_CORNER_OUTSIDE = 1,
    FE_CORNER_COLUMN = 2,
} fe_corner_kind;

typedef struct fe_corner {
    /** Where the corner line meets the floor (y = floor_y), AR world. */
    float pos[3];
    /**
     * Horizontal unit normals (x, z) of the two faces, each oriented toward
     * the camera (CornerSeenEvent contract). Ordered so that
     * face_a.x * face_b.z - face_a.z * face_b.x >= 0, which makes the pairing
     * deterministic; the Dart matcher still resolves the 90 degree ambiguity.
     */
    float face_a[2];
    float face_b[2];
    /** Angle between the two faces' surfaces, degrees: 90 for any square corner. */
    float angle_deg;
    /** fe_corner_kind. */
    int kind;
    /** How far each face was seen extending from the corner, metres. */
    float span_a;
    float span_b;
    /** RMS residual of the point fit, metres (0 for plane input). */
    float rms;
    /** Horizontal distance from the corner to the aim hint, metres. */
    float dist_to_hint;
} fe_corner;

/**
 * Corner from a point cloud (LiDAR scene depth or ARCore Depth, AR world).
 * Fits two vertical planes as 2D lines on the floor plane with RANSAC,
 * refines them by least squares and intersects them.
 *
 * hint: the point the user aimed at (the pin's depth hit), AR world.
 * camera: camera position, AR world (orients the face normals).
 * floor_y: floor height; pass floor_known = 0 when no floor plane is tracked,
 *   and the corner's y is then the hint's y (the caller should prefer to
 *   refuse and coach "point at the floor").
 * noise_m: expected depth noise (about 0.01 LiDAR, 0.03 ARCore Depth).
 * Returns 1 on success.
 */
int fe_corner_from_points(const float* xyz, size_t n, const float hint[3], const float camera[3],
                          float floor_y, int floor_known, float noise_m, fe_corner* out);

/**
 * Corner from two tracked vertical planes (ARCore Plane / ARKit
 * ARPlaneAnchor). Each plane is given by its centre, its normal and its
 * half-extent along the horizontal axis. The corner must fall within 0.6 m
 * of the hint. Returns 1 on success.
 */
int fe_corner_from_planes(const float centre_a[3], const float normal_a[3], float half_extent_a,
                          const float centre_b[3], const float normal_b[3], float half_extent_b,
                          const float hint[3], const float camera[3], float floor_y, int floor_known,
                          fe_corner* out);

/* ------------------------------------------------------------------------ */
/* Square pose from image corners                                            */
/* ------------------------------------------------------------------------ */

/**
 * Pose of a planar square of known edge length from its four image corners,
 * in order around the square (ML Kit and Vision both give them clockwise
 * from top-left). Intrinsics in pixels of the same image. Output in camera
 * space (+X right, +Y up, -Z forward): the square's centre (intersection of
 * the diagonals), its unit normal facing the camera, and the distance.
 * The normal comes from the two vanishing points of the edge pairs, which is
 * exact for a perfect square and noisy for a small one: the §4.2 "pnp"
 * method, flagged and down-weighted. Returns 1 on success.
 */
int fe_square_pose(const float corners_px[8], float fx, float fy, float cx, float cy, float edge_m,
                   float centre_cam[3], float normal_cam[3], float* distance_m);

/**
 * Mean edge length (metres) of the square whose image corners are given,
 * intersected with a known plane (camera space point and normal). Used for
 * the print-scale check (qrEdgeMm) when depth or a tracked plane gives the
 * wall. Returns a negative value when a corner ray misses the plane.
 */
float fe_square_edge_on_plane(const float corners_px[8], float fx, float fy, float cx, float cy,
                              const float plane_point_cam[3], const float plane_normal_cam[3]);

/* ------------------------------------------------------------------------ */
/* Overlay GLB                                                               */
/* ------------------------------------------------------------------------ */

typedef struct fe_grid_line {
    float x0, z0, x1, z1;
} fe_grid_line;

enum {
    FE_PIN_MARKER = 0, /* a diamond on a stem: snag, finding, clash, measure */
    FE_PIN_BOARD = 1,  /* an A4 board facing `normal`: board, ghostBoard */
};

typedef struct fe_pin {
    float pos[3];
    float normal[3]; /* used by FE_PIN_BOARD; horizontal, unit */
    uint32_t rgb;    /* 0xRRGGBB, sRGB */
    float alpha;     /* 0..1 */
    int shape;       /* FE_PIN_* */
} fe_pin;

/**
 * Builds a GLB (glTF 2.0, KHR_materials_unlit) holding dash-dot grid lines
 * with a bubble at each end on the plane y = floor_y + 0.01, plus the pins.
 * All positions are in the tile frame, so the asset goes under the model
 * root and moves with the fit. Returns a malloc'd buffer (free with
 * fe_free) and its size, or NULL when there is nothing to draw.
 */
uint8_t* fe_overlay_glb(const fe_grid_line* lines, size_t n_lines, float floor_y, uint32_t grid_rgb,
                        const fe_pin* pins, size_t n_pins, size_t* out_size);

void fe_free(void* p);

#ifdef __cplusplus
}
#endif

#endif /* FE_AR_CORE_H */
