/*
 * Unit tests for fe_ar_core, runnable on any laptop with a C compiler:
 *
 *   cc -std=c99 -Wall -Wextra -O1 -I src src/fe_ar_core.c src/test/fe_ar_core_test.c -lm -o /tmp/fe_ar_core_test
 *   /tmp/fe_ar_core_test src/test/fixtures
 *
 * Fixtures come from tool/make_core_fixtures.mjs (the real meshoptimizer
 * encoder through gltf-transform). Expected tile values below are the ones
 * that script authors; change both together.
 */
#include "../fe_ar_core.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failed = 0, g_passed = 0;

#define CHECK(cond, ...)                                          \
    do {                                                          \
        if (cond) {                                               \
            g_passed++;                                           \
        } else {                                                  \
            g_failed++;                                           \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);           \
            printf(__VA_ARGS__);                                  \
            printf("\n");                                         \
        }                                                         \
    } while (0)

#define NEAR(a, b, eps) (fabs((double) (a) - (double) (b)) <= (eps))

static uint8_t* read_file(const char* dir, const char* name, size_t* size) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", dir, name);
    FILE* f = fopen(path, "rb");
    if (!f) {
        printf("cannot open %s\n", path);
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = (uint8_t*) malloc((size_t) n);
    if (fread(buf, 1, (size_t) n, f) != (size_t) n) {
        fclose(f);
        free(buf);
        return NULL;
    }
    fclose(f);
    *size = (size_t) n;
    return buf;
}

typedef struct codec_case {
    uint32_t count, stride, raw_len, enc_len;
    const uint8_t* raw;
    const uint8_t* enc;
} codec_case;

static int load_case(const uint8_t* buf, size_t size, codec_case* c) {
    if (size < 16) return 0;
    memcpy(&c->count, buf, 4);
    memcpy(&c->stride, buf + 4, 4);
    memcpy(&c->raw_len, buf + 8, 4);
    memcpy(&c->enc_len, buf + 12, 4);
    if (16 + (size_t) c->raw_len + c->enc_len != size) return 0;
    c->raw = buf + 16;
    c->enc = buf + 16 + c->raw_len;
    return 1;
}

static uint32_t index_at(const uint8_t* p, size_t i, uint32_t size) {
    if (size == 2) {
        uint16_t v;
        memcpy(&v, p + i * 2, 2);
        return v;
    }
    uint32_t v;
    memcpy(&v, p + i * 4, 4);
    return v;
}

/* meshopt's index encoder may rotate a triangle's vertices (a,b,c -> b,c,a)
 * to compress better; winding is preserved, so compare up to rotation. */
static int same_triangles(const uint8_t* got, const uint8_t* want, uint32_t count, uint32_t size) {
    for (uint32_t t = 0; t + 2 < count; t += 3) {
        const uint32_t g[3] = {index_at(got, t, size), index_at(got, t + 1, size), index_at(got, t + 2, size)};
        const uint32_t w[3] = {index_at(want, t, size), index_at(want, t + 1, size), index_at(want, t + 2, size)};
        int ok = 0;
        for (int r = 0; r < 3 && !ok; r++) ok = g[0] == w[r] && g[1] == w[(r + 1) % 3] && g[2] == w[(r + 2) % 3];
        if (!ok) {
            printf("  triangle %u: got %u %u %u want %u %u %u\n", t / 3, g[0], g[1], g[2], w[0], w[1], w[2]);
            return 0;
        }
    }
    return 1;
}

static void test_codec(const char* dir) {
    const char* vertex_cases[] = {
        "vertex_1000_12_v0.bin", "vertex_300_16_v0.bin", "vertex_17_8_v0.bin",
        "vertex_600_16_v0.bin",  "vertex_1000_16_v1.bin", "vertex_777_12_v1.bin",
    };
    for (size_t i = 0; i < sizeof(vertex_cases) / sizeof(vertex_cases[0]); i++) {
        size_t size;
        uint8_t* buf = read_file(dir, vertex_cases[i], &size);
        codec_case c;
        CHECK(buf && load_case(buf, size, &c), "%s: fixture", vertex_cases[i]);
        if (!buf) continue;
        uint8_t* out = (uint8_t*) calloc(c.raw_len, 1);
        const int rc = fe_meshopt_decode_vertex(out, c.count, c.stride, c.enc, c.enc_len);
        CHECK(rc == 0, "%s: decode rc %d", vertex_cases[i], rc);
        CHECK(memcmp(out, c.raw, c.raw_len) == 0, "%s: decoded bytes differ", vertex_cases[i]);
        /* truncation must fail cleanly, never read out of bounds */
        const int rc2 = fe_meshopt_decode_vertex(out, c.count, c.stride, c.enc, c.enc_len / 2);
        CHECK(rc2 != 0, "%s: truncated input accepted", vertex_cases[i]);
        free(out);
        free(buf);
    }
    const char* index_cases[] = {"index_2.bin", "index_4.bin"};
    for (size_t i = 0; i < 2; i++) {
        size_t size;
        uint8_t* buf = read_file(dir, index_cases[i], &size);
        codec_case c;
        CHECK(buf && load_case(buf, size, &c), "%s: fixture", index_cases[i]);
        if (!buf) continue;
        uint8_t* out = (uint8_t*) calloc(c.raw_len, 1);
        const int rc = fe_meshopt_decode_index(out, c.count, c.stride, c.enc, c.enc_len);
        CHECK(rc == 0, "%s: decode rc %d", index_cases[i], rc);
        CHECK(same_triangles(out, c.raw, c.count, c.stride), "%s: decoded triangles differ", index_cases[i]);
        const int rc2 = fe_meshopt_decode_index(out, c.count, c.stride, c.enc, c.enc_len - 20);
        CHECK(rc2 != 0, "%s: truncated input accepted", index_cases[i]);
        free(out);
        free(buf);
    }
    {
        size_t size;
        uint8_t* buf = read_file(dir, "sequence_4.bin", &size);
        codec_case c;
        CHECK(buf && load_case(buf, size, &c), "sequence fixture");
        if (buf) {
            uint8_t* out = (uint8_t*) calloc(c.raw_len, 1);
            const int rc = fe_meshopt_decode_sequence(out, c.count, c.stride, c.enc, c.enc_len);
            CHECK(rc == 0, "sequence: decode rc %d", rc);
            CHECK(memcmp(out, c.raw, c.raw_len) == 0, "sequence: decoded indices differ");
            free(out);
            free(buf);
        }
    }
}

static void test_tile(const char* dir, const char* name) {
    size_t size;
    uint8_t* glb = read_file(dir, name, &size);
    CHECK(glb != NULL, "%s: fixture", name);
    if (!glb) return;
    char err[256];
    fe_tile* t = fe_tile_parse(glb, size, err, sizeof(err));
    CHECK(t != NULL, "%s: parse failed: %s", name, err);
    free(glb);
    if (!t) return;

    CHECK(fe_tile_triangle_count(t) == 24, "%s: triangles %u", name, fe_tile_triangle_count(t));
    CHECK(fe_tile_line_count(t) == 1, "%s: lines %u", name, fe_tile_line_count(t));
    CHECK(fe_tile_feature_count(t) == 3, "%s: features %u", name, fe_tile_feature_count(t));
    CHECK(fe_tile_feature_id(t, 0) == 7 && fe_tile_feature_id(t, 1) == 42 && fe_tile_feature_id(t, 2) == 99, "%s: feature ids", name);
    CHECK(fe_tile_feature_id(t, 3) == -1, "%s: out-of-table local index", name);
    CHECK(strcmp(fe_tile_layer(t), "mep") == 0, "%s: layer '%s'", name, fe_tile_layer(t));
    CHECK(strcmp(fe_tile_build_id(t), "build-fixture-1") == 0, "%s: buildId '%s'", name, fe_tile_build_id(t));
    CHECK(fe_tile_local_index_count(t) == 3, "%s: local index count %u", name, fe_tile_local_index_count(t));

    /* int16 normalised quantisation: step 2/32767 m, so allow a millimetre */
    const double q = 0.001;
    float mn[3], mx[3];
    CHECK(fe_tile_bounds(t, mn, mx), "%s: bounds", name);
    CHECK(NEAR(mn[0], 10, q) && NEAR(mn[1], 0, q) && NEAR(mn[2], -6, q), "%s: min %f %f %f", name, mn[0], mn[1], mn[2]);
    CHECK(NEAR(mx[0], 13, q) && NEAR(mx[1], 2, q) && NEAR(mx[2], -5, q), "%s: max %f %f %f", name, mx[0], mx[1], mx[2]);
    CHECK(fe_tile_local_bounds(t, 1, mn, mx), "%s: local bounds 1", name);
    CHECK(NEAR(mn[0], 12, q) && NEAR(mx[0], 13, q) && NEAR(mn[2], -6, q) && NEAR(mx[2], -5, q), "%s: box B bounds", name);
    CHECK(fe_tile_local_bounds(t, 2, mn, mx), "%s: local bounds 2 (line)", name);
    CHECK(NEAR(mn[1], 2, q) && NEAR(mx[1], 2, q) && NEAR(mn[0], 10, q) && NEAR(mx[0], 13, q), "%s: line bounds", name);

    /* A ray from the front (+z side) into box A's face at z = -5 */
    fe_hit hit;
    const float o1[3] = {10.5f, 0.5f, 0.0f}, d1[3] = {0, 0, -1};
    CHECK(fe_tile_raycast(t, o1, d1, 100.0f, &hit), "%s: ray into box A missed", name);
    CHECK(hit.local_index == 0 && fe_tile_feature_id(t, hit.local_index) == 7, "%s: hit local %u", name, hit.local_index);
    CHECK(NEAR(hit.t, 5.0, q) && NEAR(hit.point[2], -5.0, q), "%s: hit t %f z %f", name, hit.t, hit.point[2]);
    CHECK(NEAR(hit.normal[2], 1.0, 1e-3), "%s: hit normal %f %f %f", name, hit.normal[0], hit.normal[1], hit.normal[2]);

    /* From the side (-x) through A into B: the nearest wins (A) */
    const float o2[3] = {5.0f, 0.5f, -5.5f}, d2[3] = {1, 0, 0};
    CHECK(fe_tile_raycast(t, o2, d2, 100.0f, &hit) && hit.local_index == 0 && NEAR(hit.t, 5.0, q), "%s: side ray", name);
    /* Hiding A (skip[0]) lets the same side ray through to B */
    const uint8_t skip_a[3] = {1, 0, 0};
    CHECK(fe_tile_raycast_masked(t, o2, d2, 100.0f, skip_a, 3, &hit) && hit.local_index == 1 && NEAR(hit.t, 7.0, q), "%s: masked ray", name);
    const uint8_t skip_all[3] = {1, 1, 0};
    CHECK(!fe_tile_raycast_masked(t, o2, d2, 100.0f, skip_all, 3, &hit), "%s: all hidden still hit", name);
    /* Starting between the boxes, going +x: B */
    const float o3[3] = {11.5f, 0.5f, -5.5f};
    CHECK(fe_tile_raycast(t, o3, d2, 100.0f, &hit) && hit.local_index == 1 && NEAR(hit.t, 0.5, q), "%s: ray into B", name);
    /* max_t respected; a ray above everything misses (lines are not pickable) */
    CHECK(!fe_tile_raycast(t, o3, d2, 0.4f, &hit), "%s: max_t ignored", name);
    const float o4[3] = {11.0f, 2.0f, 0.0f};
    CHECK(!fe_tile_raycast(t, o4, d1, 100.0f, &hit), "%s: picked a line", name);
    /* non-unit direction: t in units of |dir| */
    const float d5[3] = {0, 0, -2};
    CHECK(fe_tile_raycast(t, o1, d5, 100.0f, &hit) && NEAR(hit.t, 2.5, q), "%s: scaled dir t %f", name, hit.t);
    fe_tile_free(t);
}

static void test_bad_input(void) {
    char err[128];
    const uint8_t junk[40] = {'g', 'l', 'T', 'F', 2, 0, 0, 0, 40, 0, 0, 0};
    CHECK(fe_tile_parse(junk, sizeof(junk), err, sizeof(err)) == NULL, "junk GLB accepted");
    CHECK(fe_tile_parse(NULL, 0, err, sizeof(err)) == NULL, "NULL accepted");
    /* A GLB with malformed JSON */
    const char* bad_json = "{\"asset\":{\"version\":\"2.0\"},\"nodes\":[";
    uint8_t buf[128] = {0};
    const uint32_t jl = (uint32_t) ((strlen(bad_json) + 3) & ~3u);
    const uint32_t total = 12 + 8 + jl;
    const uint32_t hdr[5] = {0x46546C67u, 2u, total, jl, 0x4E4F534Au};
    memcpy(buf, hdr, 20);
    memset(buf + 20, ' ', jl);
    memcpy(buf + 20, bad_json, strlen(bad_json));
    CHECK(fe_tile_parse(buf, total, err, sizeof(err)) == NULL, "malformed JSON accepted");
    CHECK(strstr(err, "JSON") != NULL, "error text '%s'", err);
}

/* A corrupted or truncated download must fail cleanly: run with
 * -fsanitize=address,undefined to make any out-of-bounds read fatal. */
static void test_corruption(const char* dir) {
    size_t size;
    uint8_t* glb = read_file(dir, "tile_quantize.glb", &size);
    if (!glb) return;
    uint8_t* copy = (uint8_t*) malloc(size);
    unsigned s = 4242;
    int parsed = 0;
    for (int it = 0; it < 3000; it++) {
        memcpy(copy, glb, size);
        const int flips = 1 + it % 6;
        for (int f = 0; f < flips; f++) {
            s = s * 1664525u + 1013904223u;
            const size_t at = 12 + (s >> 8) % (size - 12);
            s = s * 1664525u + 1013904223u;
            copy[at] = (uint8_t) (s >> 24);
        }
        s = s * 1664525u + 1013904223u;
        const size_t len = (it % 5 == 0) ? 12 + (s >> 8) % (size - 12) : size; /* sometimes truncate */
        char err[128];
        fe_tile* t = fe_tile_parse(copy, len, err, sizeof(err));
        if (t) {
            parsed++;
            const float o[3] = {10.5f, 0.5f, 0.0f}, d[3] = {0, 0, -1};
            fe_hit hit;
            fe_tile_raycast(t, o, d, 100.0f, &hit);
            float mn[3], mx[3];
            for (uint32_t l = 0; l < 4; l++) fe_tile_local_bounds(t, l, mn, mx);
            fe_tile_free(t);
        }
    }
    CHECK(1, "corruption loop survived");
    printf("corruption: %d of 3000 damaged tiles still parsed (the rest were rejected)\n", parsed);
    free(copy);
    free(glb);
}

static void test_fit_plane(void) {
    /* points on the plane x + y + z = 3 with a little noise */
    float pts[300];
    unsigned s = 7;
    for (int i = 0; i < 100; i++) {
        s = s * 1664525u + 1013904223u;
        const float a = (float) (s % 1000) / 500.0f - 1.0f;
        s = s * 1664525u + 1013904223u;
        const float b = (float) (s % 1000) / 500.0f - 1.0f;
        pts[i * 3] = a;
        pts[i * 3 + 1] = b;
        pts[i * 3 + 2] = 3.0f - a - b;
    }
    float c[3], n[3], rms;
    CHECK(fe_fit_plane(pts, 100, c, n, &rms), "plane fit failed");
    const float k = 1.0f / sqrtf(3.0f);
    CHECK(NEAR(fabs(n[0]), k, 1e-4) && NEAR(fabs(n[1]), k, 1e-4) && NEAR(fabs(n[2]), k, 1e-4), "plane normal %f %f %f", n[0], n[1], n[2]);
    CHECK(rms < 1e-4f, "plane rms %f", rms);
    CHECK(!fe_fit_plane(pts, 2, c, n, &rms), "2 points accepted");
}

/* Builds a point cloud of two vertical walls meeting at (cx, cz), each
 * extending `len` along its direction, heights 0.2..2.2 above floor 0. */
static size_t make_walls(float* out, float cx, float cz, float ax, float az, float bx, float bz, float len, float noise) {
    size_t n = 0;
    unsigned s = 99;
    for (int w = 0; w < 2; w++) {
        const float dx = w ? bx : ax, dz = w ? bz : az;
        for (int i = 0; i < 40; i++) {
            for (int h = 0; h < 10; h++) {
                s = s * 1664525u + 1013904223u;
                const float e = ((float) (s % 1000) / 500.0f - 1.0f) * noise;
                const float t = len * (float) (i + 1) / 40.0f;
                /* noise across the wall, along its normal (-dz, dx) */
                out[n * 3] = cx + dx * t - dz * e;
                out[n * 3 + 1] = 0.2f + 0.2f * (float) h;
                out[n * 3 + 2] = cz + dz * t + dx * e;
                n++;
            }
        }
    }
    return n;
}

static void test_corners(void) {
    static float pts[3 * 2000];
    fe_corner c;
    /* Inside corner at (2, -3): walls running +x and +z, camera inside the room. */
    size_t n = make_walls(pts, 2.0f, -3.0f, 1, 0, 0, 1, 1.4f, 0.005f);
    const float hint[3] = {2.1f, 1.2f, -2.9f}, cam_in[3] = {3.5f, 1.5f, -1.5f};
    CHECK(fe_corner_from_points(pts, n, hint, cam_in, 0.0f, 1, 0.01f, &c), "inside corner not found");
    CHECK(NEAR(c.pos[0], 2.0, 0.01) && NEAR(c.pos[2], -3.0, 0.01) && NEAR(c.pos[1], 0.0, 1e-6), "inside pos %f %f %f", c.pos[0], c.pos[1], c.pos[2]);
    CHECK(c.kind == FE_CORNER_INSIDE, "inside kind %d", c.kind);
    CHECK(NEAR(c.angle_deg, 90.0, 1.0), "inside angle %f", c.angle_deg);
    /* both normals face the camera: (0, 1) and (1, 0) in (x, z) */
    const int has_z = (NEAR(c.face_a[1], 1.0, 0.02) || NEAR(c.face_b[1], 1.0, 0.02));
    const int has_x = (NEAR(c.face_a[0], 1.0, 0.02) || NEAR(c.face_b[0], 1.0, 0.02));
    CHECK(has_x && has_z, "inside faces (%f,%f) (%f,%f)", c.face_a[0], c.face_a[1], c.face_b[0], c.face_b[1]);
    CHECK(c.face_a[0] * c.face_b[1] - c.face_a[1] * c.face_b[0] >= 0, "face order");

    /* Outside corner of a 0.6 m column whose solid occupies x < 0, z < 0:
     * the camera in the +x,+z quadrant sees the face on z = 0 (running -x)
     * and the face on x = 0 (running -z). */
    n = make_walls(pts, 0.0f, 0.0f, -1, 0, 0, -1, 0.6f, 0.005f);
    const float hint2[3] = {0.05f, 1.0f, 0.05f}, cam_out[3] = {1.5f, 1.5f, 1.5f};
    CHECK(fe_corner_from_points(pts, n, hint2, cam_out, 0.0f, 1, 0.01f, &c), "column corner not found");
    CHECK(NEAR(c.pos[0], 0.0, 0.01) && NEAR(c.pos[2], 0.0, 0.01), "column pos %f %f", c.pos[0], c.pos[2]);
    CHECK(c.kind == FE_CORNER_COLUMN, "column kind %d", c.kind);
    CHECK(NEAR(c.angle_deg, 90.0, 1.0), "column angle %f", c.angle_deg);

    /* A flat wall is not a corner */
    n = 0;
    for (int i = 0; i < 80; i++)
        for (int h = 0; h < 8; h++) {
            pts[n * 3] = -1.0f + 0.025f * (float) i;
            pts[n * 3 + 1] = 0.3f + 0.2f * (float) h;
            pts[n * 3 + 2] = -2.0f;
            n++;
        }
    const float hint3[3] = {0.0f, 1.0f, -2.0f}, cam3[3] = {0.0f, 1.5f, 0.0f};
    CHECK(!fe_corner_from_points(pts, n, hint3, cam3, 0.0f, 1, 0.01f, &c), "flat wall reported as a corner");

    /* Planes: inside corner at (1, 1), walls along x (normal +z) and along z (normal +x) */
    const float ca[3] = {2.0f, 1.2f, 1.0f}, na[3] = {0, 0, 1};
    const float cb[3] = {1.0f, 1.2f, 2.5f}, nb[3] = {1, 0, 0};
    const float hint4[3] = {1.1f, 1.2f, 1.1f}, cam4[3] = {3.0f, 1.6f, 3.0f};
    CHECK(fe_corner_from_planes(ca, na, 1.0f, cb, nb, 1.5f, hint4, cam4, -0.3f, 1, &c), "plane corner not found");
    CHECK(NEAR(c.pos[0], 1.0, 1e-4) && NEAR(c.pos[2], 1.0, 1e-4) && NEAR(c.pos[1], -0.3, 1e-6), "plane corner pos %f %f %f", c.pos[0], c.pos[1], c.pos[2]);
    CHECK(c.kind == FE_CORNER_INSIDE && NEAR(c.angle_deg, 90.0, 0.1), "plane corner kind %d angle %f", c.kind, c.angle_deg);
    /* normals flipped away from the camera must come back toward it */
    const float na_flip[3] = {0, 0, -1};
    CHECK(fe_corner_from_planes(ca, na_flip, 1.0f, cb, nb, 1.5f, hint4, cam4, 0.0f, 1, &c), "flipped plane");
    CHECK((NEAR(c.face_a[1], 1.0, 1e-4) || NEAR(c.face_b[1], 1.0, 1e-4)), "normal toward camera");
    /* too far from the hint */
    const float hint5[3] = {3.0f, 1.2f, 3.0f};
    CHECK(!fe_corner_from_planes(ca, na, 1.0f, cb, nb, 1.5f, hint5, cam4, 0.0f, 1, &c), "far corner accepted");
    /* parallel planes */
    CHECK(!fe_corner_from_planes(ca, na, 1.0f, cb, na, 1.5f, hint4, cam4, 0.0f, 1, &c), "parallel planes accepted");
}

/* Projects world point (camera space) to pixels. */
static void project(const double p[3], double fx, double fy, double cx, double cy, float* u, float* v) {
    *u = (float) (cx + fx * (p[0] / -p[2]));
    *v = (float) (cy - fy * (p[1] / -p[2]));
}

static void test_square_pose(void) {
    const double fx = 1000, fy = 1000, cx = 640, cy = 360, edge = 0.115;
    /* A square 1.2 m in front, rotated 25 degrees about the vertical axis. */
    const double th = 25.0 * 3.14159265358979 / 180.0;
    const double centre[3] = {0.1, -0.05, -1.2};
    const double right[3] = {cos(th), 0, sin(th)}, up[3] = {0, 1, 0};
    const double normal[3] = {-sin(th), 0, cos(th)}; /* faces the camera (+z-ish) */
    const double h = edge / 2;
    const double corners[4][2] = {{-h, h}, {h, h}, {h, -h}, {-h, -h}}; /* TL, TR, BR, BL */
    float px[8];
    for (int i = 0; i < 4; i++) {
        double p[3];
        for (int k = 0; k < 3; k++) p[k] = centre[k] + right[k] * corners[i][0] + up[k] * corners[i][1];
        project(p, fx, fy, cx, cy, &px[i * 2], &px[i * 2 + 1]);
    }
    float c[3], n[3], dist;
    CHECK(fe_square_pose(px, (float) fx, (float) fy, (float) cx, (float) cy, (float) edge, c, n, &dist), "square pose failed");
    CHECK(NEAR(c[0], centre[0], 0.003) && NEAR(c[1], centre[1], 0.003) && NEAR(c[2], centre[2], 0.005), "square centre %f %f %f", c[0], c[1], c[2]);
    CHECK(NEAR(n[0], normal[0], 0.01) && NEAR(n[1], normal[1], 0.01) && NEAR(n[2], normal[2], 0.01), "square normal %f %f %f", n[0], n[1], n[2]);
    const double d = sqrt(centre[0] * centre[0] + centre[1] * centre[1] + centre[2] * centre[2]);
    CHECK(NEAR(dist, d, 0.005), "square distance %f vs %f", dist, d);
    /* the metric edge on the true plane */
    const float pp[3] = {(float) centre[0], (float) centre[1], (float) centre[2]};
    const float pn[3] = {(float) normal[0], (float) normal[1], (float) normal[2]};
    const float e = fe_square_edge_on_plane(px, (float) fx, (float) fy, (float) cx, (float) cy, pp, pn);
    CHECK(NEAR(e, edge, 0.0005), "edge on plane %f", e);
}

static void test_overlay(void) {
    const fe_grid_line lines[2] = {{0, 0, 10, 0}, {0, 0, 0, 8}};
    fe_pin pins[2];
    memset(pins, 0, sizeof(pins));
    pins[0].pos[0] = 3;
    pins[0].pos[1] = 1;
    pins[0].pos[2] = 4;
    pins[0].rgb = 0xEF4444;
    pins[0].alpha = 1;
    pins[0].shape = FE_PIN_MARKER;
    pins[1].pos[0] = 5;
    pins[1].pos[1] = 1.5f;
    pins[1].pos[2] = 0;
    pins[1].normal[2] = 1;
    pins[1].rgb = 0x0EA5E9;
    pins[1].alpha = 0.45f;
    pins[1].shape = FE_PIN_BOARD;
    size_t size = 0;
    uint8_t* glb = fe_overlay_glb(lines, 2, -0.2f, 0xF59E0B, pins, 2, &size);
    CHECK(glb != NULL && size > 100 && (size % 4) == 0, "overlay GLB size %zu", size);
    if (!glb) return;
    /* Round trip through our own parser: triangles are the diamond (8) and the board (2). */
    char err[128];
    fe_tile* t = fe_tile_parse(glb, size, err, sizeof(err));
    CHECK(t != NULL, "overlay GLB does not parse: %s", err);
    if (t) {
        CHECK(fe_tile_triangle_count(t) == 10, "overlay triangles %u", fe_tile_triangle_count(t));
        CHECK(fe_tile_line_count(t) > 20, "overlay lines %u", fe_tile_line_count(t));
        float mn[3], mx[3];
        fe_tile_bounds(t, mn, mx);
        CHECK(NEAR(mn[1], -0.19, 1e-4), "grid height %f", mn[1]);
        CHECK(mx[0] > 10.2f && mn[0] < -0.2f, "bubbles beyond the line ends %f %f", mn[0], mx[0]);
        const float o[3] = {3.0f, 5.0f, 4.0f}, d[3] = {0, -1, 0};
        fe_hit hit;
        CHECK(fe_tile_raycast(t, o, d, 10, &hit) && NEAR(hit.point[1], 1.39, 0.001), "pin diamond top at %f", hit.point[1]);
        fe_tile_free(t);
    }
    fe_free(glb);
    CHECK(fe_overlay_glb(NULL, 0, 0, 0, NULL, 0, &size) == NULL && size == 0, "empty overlay should be NULL");
}

int main(int argc, char** argv) {
    const char* dir = argc > 1 ? argv[1] : "src/test/fixtures";
    test_codec(dir);
    test_tile(dir, "tile_quantize.glb");
    test_tile(dir, "tile_filter.glb");
    test_bad_input();
    test_corruption(dir);
    test_fit_plane();
    test_corners();
    test_square_pose();
    test_overlay();
    printf("%d passed, %d failed\n", g_passed, g_failed);
    return g_failed ? 1 : 0;
}
