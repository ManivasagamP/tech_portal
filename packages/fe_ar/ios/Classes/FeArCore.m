#import "FeArCore.h"

#include "../../src/fe_ar_core.h"

@implementation FeArRayHit {
  @public
    float _t;
    simd_float3 _point;
    simd_float3 _normal;
    NSInteger _localIndex;
}
- (float)t {
    return _t;
}
- (simd_float3)point {
    return _point;
}
- (simd_float3)normal {
    return _normal;
}
- (NSInteger)localIndex {
    return _localIndex;
}
@end

@implementation FeArCpuTile {
    fe_tile* _tile;
    NSString* _layer;
    NSString* _buildId;
    NSData* _featureIds;
}

- (nullable instancetype)initWithData:(NSData*)glb error:(NSString* _Nullable*)error {
    if ((self = [super init])) {
        char err[256] = {0};
        _tile = fe_tile_parse((const uint8_t*)glb.bytes, glb.length, err, sizeof(err));
        if (!_tile) {
            if (error) *error = [NSString stringWithUTF8String:err[0] ? err : "parse failed"];
            return nil;
        }
        _layer = [NSString stringWithUTF8String:fe_tile_layer(_tile)] ?: @"";
        _buildId = [NSString stringWithUTF8String:fe_tile_build_id(_tile)] ?: @"";
        const uint32_t n = fe_tile_feature_count(_tile);
        const int32_t* ids = fe_tile_feature_ids(_tile);
        _featureIds = n && ids ? [NSData dataWithBytes:ids length:n * sizeof(int32_t)] : [NSData data];
    }
    return self;
}

- (void)dealloc {
    fe_tile_free(_tile);
}

- (NSString*)layer {
    return _layer;
}
- (NSString*)buildId {
    return _buildId;
}
- (NSData*)featureIds {
    return _featureIds;
}
- (NSInteger)triangleCount {
    return fe_tile_triangle_count(_tile);
}
- (NSInteger)localIndexCount {
    return fe_tile_local_index_count(_tile);
}

- (NSInteger)featureIdAt:(NSInteger)localIndex {
    if (localIndex < 0) return -1;
    return fe_tile_feature_id(_tile, (uint32_t)localIndex);
}

- (BOOL)localBounds:(NSInteger)localIndex min:(simd_float3*)outMin max:(simd_float3*)outMax {
    float mn[3], mx[3];
    if (localIndex < 0 || !fe_tile_local_bounds(_tile, (uint32_t)localIndex, mn, mx)) return NO;
    *outMin = simd_make_float3(mn[0], mn[1], mn[2]);
    *outMax = simd_make_float3(mx[0], mx[1], mx[2]);
    return YES;
}

- (nullable FeArRayHit*)raycastOrigin:(simd_float3)origin
                            direction:(simd_float3)direction
                                 maxT:(float)maxT
                             skipMask:(nullable NSData*)skipMask {
    const float o[3] = {origin.x, origin.y, origin.z};
    const float d[3] = {direction.x, direction.y, direction.z};
    fe_hit hit;
    if (!fe_tile_raycast_masked(_tile, o, d, maxT, (const uint8_t*)skipMask.bytes, (uint32_t)skipMask.length, &hit)) return nil;
    FeArRayHit* r = [FeArRayHit new];
    r->_t = hit.t;
    r->_point = simd_make_float3(hit.point[0], hit.point[1], hit.point[2]);
    r->_normal = simd_make_float3(hit.normal[0], hit.normal[1], hit.normal[2]);
    r->_localIndex = hit.local_index == FE_NO_FEATURE ? -1 : (NSInteger)hit.local_index;
    return r;
}
@end

@implementation FeArCorner {
  @public
    fe_corner _c;
}
- (simd_float3)position {
    return simd_make_float3(_c.pos[0], _c.pos[1], _c.pos[2]);
}
- (simd_float2)faceA {
    return simd_make_float2(_c.face_a[0], _c.face_a[1]);
}
- (simd_float2)faceB {
    return simd_make_float2(_c.face_b[0], _c.face_b[1]);
}
- (float)angleDeg {
    return _c.angle_deg;
}
- (NSInteger)kind {
    return _c.kind;
}
- (float)spanA {
    return _c.span_a;
}
- (float)spanB {
    return _c.span_b;
}
- (float)rms {
    return _c.rms;
}
@end

static void fe_v3(simd_float3 v, float out[3]) {
    out[0] = v.x;
    out[1] = v.y;
    out[2] = v.z;
}

@implementation FeArGeometry

+ (nullable FeArCorner*)cornerFromPoints:(NSData*)xyz
                                    hint:(simd_float3)hint
                                  camera:(simd_float3)camera
                                  floorY:(float)floorY
                              floorKnown:(BOOL)floorKnown
                                  noiseM:(float)noiseM {
    float h[3], c[3];
    fe_v3(hint, h);
    fe_v3(camera, c);
    FeArCorner* r = [FeArCorner new];
    const size_t n = xyz.length / (3 * sizeof(float));
    if (!fe_corner_from_points((const float*)xyz.bytes, n, h, c, floorY, floorKnown ? 1 : 0, noiseM, &r->_c)) return nil;
    return r;
}

+ (nullable FeArCorner*)cornerFromPlaneCentre:(simd_float3)centreA
                                       normal:(simd_float3)normalA
                                   halfExtent:(float)halfA
                                  otherCentre:(simd_float3)centreB
                                  otherNormal:(simd_float3)normalB
                              otherHalfExtent:(float)halfB
                                         hint:(simd_float3)hint
                                       camera:(simd_float3)camera
                                       floorY:(float)floorY
                                   floorKnown:(BOOL)floorKnown {
    float ca[3], na[3], cb[3], nb[3], h[3], c[3];
    fe_v3(centreA, ca);
    fe_v3(normalA, na);
    fe_v3(centreB, cb);
    fe_v3(normalB, nb);
    fe_v3(hint, h);
    fe_v3(camera, c);
    FeArCorner* r = [FeArCorner new];
    if (!fe_corner_from_planes(ca, na, halfA, cb, nb, halfB, h, c, floorY, floorKnown ? 1 : 0, &r->_c)) return nil;
    return r;
}

+ (BOOL)fitPlane:(NSData*)xyz centroid:(simd_float3*)centroid normal:(simd_float3*)normal rms:(float*)rms {
    float c[3], n[3], r = 0;
    const size_t count = xyz.length / (3 * sizeof(float));
    if (!fe_fit_plane((const float*)xyz.bytes, count, c, n, &r)) return NO;
    *centroid = simd_make_float3(c[0], c[1], c[2]);
    *normal = simd_make_float3(n[0], n[1], n[2]);
    if (rms) *rms = r;
    return YES;
}

+ (BOOL)squarePoseCorners:(const float*)corners
                       fx:(float)fx
                       fy:(float)fy
                       cx:(float)cx
                       cy:(float)cy
                    edgeM:(float)edgeM
                   centre:(simd_float3*)centre
                   normal:(simd_float3*)normal
                 distance:(float*)distance {
    float c[3], n[3], d = 0;
    if (!fe_square_pose(corners, fx, fy, cx, cy, edgeM, c, n, &d)) return NO;
    *centre = simd_make_float3(c[0], c[1], c[2]);
    *normal = simd_make_float3(n[0], n[1], n[2]);
    *distance = d;
    return YES;
}

+ (float)squareEdgeCorners:(const float*)corners
                        fx:(float)fx
                        fy:(float)fy
                        cx:(float)cx
                        cy:(float)cy
                planePoint:(simd_float3)planePoint
               planeNormal:(simd_float3)planeNormal {
    float p[3], n[3];
    fe_v3(planePoint, p);
    fe_v3(planeNormal, n);
    return fe_square_edge_on_plane(corners, fx, fy, cx, cy, p, n);
}

+ (nullable NSData*)overlayGlbLines:(nullable NSData*)lines
                             floorY:(float)floorY
                            gridRgb:(uint32_t)gridRgb
                               pins:(nullable NSData*)pins
                             pinRgb:(nullable NSData*)pinRgb {
    const size_t nl = lines.length / (4 * sizeof(float));
    const size_t np = pins.length / (8 * sizeof(float));
    if (np && pinRgb.length < np * sizeof(int32_t)) return nil;
    fe_grid_line* gl = (fe_grid_line*)calloc(nl ? nl : 1, sizeof(fe_grid_line));
    fe_pin* pp = (fe_pin*)calloc(np ? np : 1, sizeof(fe_pin));
    NSData* out = nil;
    if (gl && pp) {
        const float* l = (const float*)lines.bytes;
        for (size_t i = 0; i < nl; i++) {
            gl[i].x0 = l[i * 4];
            gl[i].z0 = l[i * 4 + 1];
            gl[i].x1 = l[i * 4 + 2];
            gl[i].z1 = l[i * 4 + 3];
        }
        const float* p = (const float*)pins.bytes;
        const int32_t* rgb = (const int32_t*)pinRgb.bytes;
        for (size_t i = 0; i < np; i++) {
            const float* s = p + i * 8;
            pp[i].pos[0] = s[0];
            pp[i].pos[1] = s[1];
            pp[i].pos[2] = s[2];
            pp[i].normal[0] = s[3];
            pp[i].normal[1] = s[4];
            pp[i].normal[2] = s[5];
            pp[i].alpha = s[6];
            pp[i].shape = (int)s[7];
            pp[i].rgb = (uint32_t)rgb[i] & 0xFFFFFFu;
        }
        size_t size = 0;
        uint8_t* glb = fe_overlay_glb(gl, nl, floorY, gridRgb & 0xFFFFFFu, pp, np, &size);
        if (glb) {
            out = [NSData dataWithBytes:glb length:size];
            fe_free(glb);
        }
    }
    free(gl);
    free(pp);
    return out;
}

@end
