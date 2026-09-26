/*
 * fe_ar_core.c: see fe_ar_core.h for what this is and why it is C.
 *
 * Sections:
 *   1. small helpers
 *   2. JSON (a compact DOM parser: glTF JSON is small and trusted-ish, but a
 *      corrupt download must fail cleanly, never crash)
 *   3. meshopt decoding (port of meshopt_decoder_reference.js)
 *   4. GLB tile parsing into a pick mesh
 *   5. ray casting and per-feature bounds
 *   6. plane fit and corners
 *   7. square pose
 *   8. overlay GLB builder
 *
 * Locale: nothing here calls strtod or printf("%f"). A host that set a
 * comma-decimal C locale (an Arabic or German device, a plugin calling
 * setlocale) would otherwise break JSON numbers in both directions.
 */
#include "fe_ar_core.h"

#include <float.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ======================================================================== */
/* 1. helpers                                                               */
/* ======================================================================== */

static void fe_err(char* err, size_t cap, const char* fmt, ...) {
    if (!err || cap == 0) return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, cap, fmt, ap);
    va_end(ap);
}

void fe_free(void* p) { free(p); }

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

static const double FE_PI = 3.14159265358979323846;

/* ======================================================================== */
/* 2. JSON                                                                  */
/* ======================================================================== */

typedef enum { FJ_NULL, FJ_BOOL, FJ_NUMBER, FJ_STRING, FJ_ARRAY, FJ_OBJECT } fj_kind;

typedef struct fj_node {
    fj_kind kind;
    int boolean;
    double number;
    char* string;
    size_t count;
    struct fj_node* items;
    char** keys;
} fj_node;

typedef struct fj_parser {
    const char* p;
    const char* end;
    int depth;
} fj_parser;

static void fj_free(fj_node* n) {
    if (!n) return;
    if (n->kind == FJ_STRING) free(n->string);
    if (n->kind == FJ_ARRAY || n->kind == FJ_OBJECT) {
        for (size_t i = 0; i < n->count; i++) {
            fj_free(&n->items[i]);
            if (n->keys) free(n->keys[i]);
        }
        free(n->items);
        free(n->keys);
    }
    memset(n, 0, sizeof(*n));
}

static void fj_ws(fj_parser* ps) {
    while (ps->p < ps->end && (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r')) ps->p++;
}

static int fj_hex4(const char* s, uint32_t* out) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++) {
        char c = s[i];
        int d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else return 0;
        v = (v << 4) | (uint32_t) d;
    }
    *out = v;
    return 1;
}

static void fj_put_utf8(char** w, uint32_t cp) {
    char* o = *w;
    if (cp < 0x80) {
        *o++ = (char) cp;
    } else if (cp < 0x800) {
        *o++ = (char) (0xC0 | (cp >> 6));
        *o++ = (char) (0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
        *o++ = (char) (0xE0 | (cp >> 12));
        *o++ = (char) (0x80 | ((cp >> 6) & 0x3F));
        *o++ = (char) (0x80 | (cp & 0x3F));
    } else {
        *o++ = (char) (0xF0 | (cp >> 18));
        *o++ = (char) (0x80 | ((cp >> 12) & 0x3F));
        *o++ = (char) (0x80 | ((cp >> 6) & 0x3F));
        *o++ = (char) (0x80 | (cp & 0x3F));
    }
    *w = o;
}

/* Unescaped output is never longer than the escaped input (\uXXXX is 6 bytes
 * for at most 3 of UTF-8; a surrogate pair is 12 for 4), so one allocation of
 * the raw length is enough. */
static int fj_string(fj_parser* ps, char** out) {
    if (ps->p >= ps->end || *ps->p != '"') return 0;
    const char* start = ps->p + 1;
    const char* q = start;
    while (q < ps->end && *q != '"') {
        if (*q == '\\') {
            q++;
            if (q >= ps->end) return 0;
        }
        q++;
    }
    if (q >= ps->end) return 0;
    char* buf = (char*) malloc((size_t) (q - start) + 1);
    if (!buf) return 0;
    char* w = buf;
    const char* r = start;
    while (r < q) {
        char c = *r++;
        if (c != '\\') {
            *w++ = c;
            continue;
        }
        char e = *r++;
        switch (e) {
            case '"': *w++ = '"'; break;
            case '\\': *w++ = '\\'; break;
            case '/': *w++ = '/'; break;
            case 'b': *w++ = '\b'; break;
            case 'f': *w++ = '\f'; break;
            case 'n': *w++ = '\n'; break;
            case 'r': *w++ = '\r'; break;
            case 't': *w++ = '\t'; break;
            case 'u': {
                uint32_t cp;
                if (q - r < 4 || !fj_hex4(r, &cp)) {
                    free(buf);
                    return 0;
                }
                r += 4;
                if (cp >= 0xD800 && cp <= 0xDBFF && q - r >= 6 && r[0] == '\\' && r[1] == 'u') {
                    uint32_t lo;
                    if (fj_hex4(r + 2, &lo) && lo >= 0xDC00 && lo <= 0xDFFF) {
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        r += 6;
                    }
                }
                fj_put_utf8(&w, cp);
                break;
            }
            default:
                free(buf);
                return 0;
        }
    }
    *w = 0;
    ps->p = q + 1;
    *out = buf;
    return 1;
}

/* Locale-independent number parser. Keeps up to 18 significant digits, which
 * is more than a double carries; exact for every integer up to 2^53. */
static int fj_number(fj_parser* ps, double* out) {
    const char* p = ps->p;
    const char* end = ps->end;
    int neg = 0;
    if (p < end && *p == '-') {
        neg = 1;
        p++;
    }
    if (p >= end || *p < '0' || *p > '9') return 0;
    double mant = 0.0;
    int exp10 = 0;
    int digits = 0;
    while (p < end && *p >= '0' && *p <= '9') {
        if (digits < 18) {
            mant = mant * 10.0 + (double) (*p - '0');
            if (mant != 0.0) digits++;
        } else {
            exp10++;
        }
        p++;
    }
    if (p < end && *p == '.') {
        p++;
        if (p >= end || *p < '0' || *p > '9') return 0;
        while (p < end && *p >= '0' && *p <= '9') {
            if (digits < 18) {
                mant = mant * 10.0 + (double) (*p - '0');
                if (mant != 0.0) digits++;
                exp10--;
            }
            p++;
        }
    }
    if (p < end && (*p == 'e' || *p == 'E')) {
        p++;
        int esign = 1;
        if (p < end && (*p == '+' || *p == '-')) {
            if (*p == '-') esign = -1;
            p++;
        }
        if (p >= end || *p < '0' || *p > '9') return 0;
        int e = 0;
        while (p < end && *p >= '0' && *p <= '9') {
            if (e < 10000) e = e * 10 + (*p - '0');
            p++;
        }
        exp10 += esign * e;
    }
    double v = mant;
    if (exp10 > 0) v *= pow(10.0, (double) exp10);
    else if (exp10 < 0) v /= pow(10.0, (double) -exp10);
    *out = neg ? -v : v;
    ps->p = p;
    return 1;
}

static int fj_value(fj_parser* ps, fj_node* out);

static int fj_array(fj_parser* ps, fj_node* out) {
    out->kind = FJ_ARRAY;
    ps->p++; /* '[' */
    size_t cap = 0;
    fj_ws(ps);
    if (ps->p < ps->end && *ps->p == ']') {
        ps->p++;
        return 1;
    }
    for (;;) {
        if (out->count == cap) {
            cap = cap ? cap * 2 : 8;
            fj_node* ni = (fj_node*) realloc(out->items, cap * sizeof(fj_node));
            if (!ni) return 0;
            out->items = ni;
        }
        if (!fj_value(ps, &out->items[out->count])) return 0;
        out->count++;
        fj_ws(ps);
        if (ps->p >= ps->end) return 0;
        if (*ps->p == ',') {
            ps->p++;
            continue;
        }
        if (*ps->p == ']') {
            ps->p++;
            return 1;
        }
        return 0;
    }
}

static int fj_object(fj_parser* ps, fj_node* out) {
    out->kind = FJ_OBJECT;
    ps->p++; /* '{' */
    size_t cap = 0;
    fj_ws(ps);
    if (ps->p < ps->end && *ps->p == '}') {
        ps->p++;
        return 1;
    }
    for (;;) {
        if (out->count == cap) {
            cap = cap ? cap * 2 : 8;
            fj_node* ni = (fj_node*) realloc(out->items, cap * sizeof(fj_node));
            if (!ni) return 0;
            out->items = ni;
            char** nk = (char**) realloc(out->keys, cap * sizeof(char*));
            if (!nk) return 0;
            out->keys = nk;
        }
        fj_ws(ps);
        char* key = NULL;
        if (!fj_string(ps, &key)) return 0;
        fj_ws(ps);
        if (ps->p >= ps->end || *ps->p != ':') {
            free(key);
            return 0;
        }
        ps->p++;
        if (!fj_value(ps, &out->items[out->count])) {
            free(key);
            return 0;
        }
        out->keys[out->count] = key;
        out->count++;
        fj_ws(ps);
        if (ps->p >= ps->end) return 0;
        if (*ps->p == ',') {
            ps->p++;
            continue;
        }
        if (*ps->p == '}') {
            ps->p++;
            return 1;
        }
        return 0;
    }
}

static int fj_literal(fj_parser* ps, const char* lit) {
    size_t n = strlen(lit);
    if ((size_t) (ps->end - ps->p) < n || memcmp(ps->p, lit, n) != 0) return 0;
    ps->p += n;
    return 1;
}

static int fj_value(fj_parser* ps, fj_node* out) {
    memset(out, 0, sizeof(*out));
    if (++ps->depth > 64) {
        ps->depth--;
        return 0;
    }
    fj_ws(ps);
    int ok = 0;
    if (ps->p < ps->end) {
        char c = *ps->p;
        if (c == '{') {
            ok = fj_object(ps, out);
        } else if (c == '[') {
            ok = fj_array(ps, out);
        } else if (c == '"') {
            out->kind = FJ_STRING;
            ok = fj_string(ps, &out->string);
        } else if (c == 't') {
            out->kind = FJ_BOOL;
            out->boolean = 1;
            ok = fj_literal(ps, "true");
        } else if (c == 'f') {
            out->kind = FJ_BOOL;
            ok = fj_literal(ps, "false");
        } else if (c == 'n') {
            out->kind = FJ_NULL;
            ok = fj_literal(ps, "null");
        } else {
            out->kind = FJ_NUMBER;
            ok = fj_number(ps, &out->number);
        }
    }
    ps->depth--;
    if (!ok) fj_free(out);
    return ok;
}

static int fj_parse(const char* text, size_t len, fj_node* out) {
    fj_parser ps = {text, text + len, 0};
    if (!fj_value(&ps, out)) return 0;
    fj_ws(&ps);
    /* GLB pads the JSON chunk with spaces; anything else trailing is an error. */
    while (ps.p < ps.end && (*ps.p == 0)) ps.p++;
    if (ps.p != ps.end) {
        fj_free(out);
        return 0;
    }
    return 1;
}

static const fj_node* fj_get(const fj_node* o, const char* key) {
    if (!o || o->kind != FJ_OBJECT) return NULL;
    for (size_t i = 0; i < o->count; i++) {
        if (strcmp(o->keys[i], key) == 0) return &o->items[i];
    }
    return NULL;
}

static const fj_node* fj_at(const fj_node* a, size_t i) {
    if (!a || a->kind != FJ_ARRAY || i >= a->count) return NULL;
    return &a->items[i];
}

static size_t fj_len(const fj_node* a) { return (a && a->kind == FJ_ARRAY) ? a->count : 0; }

static double fj_num(const fj_node* n, double def) { return (n && n->kind == FJ_NUMBER) ? n->number : def; }

static int64_t fj_i64(const fj_node* n, int64_t def) {
    if (!n || n->kind != FJ_NUMBER) return def;
    double v = n->number;
    if (v != v || v < -9007199254740992.0 || v > 9007199254740992.0) return def;
    return (int64_t) v;
}

static const char* fj_str(const fj_node* n) { return (n && n->kind == FJ_STRING) ? n->string : NULL; }

static int fj_bool(const fj_node* n, int def) { return (n && n->kind == FJ_BOOL) ? n->boolean : def; }

/* ======================================================================== */
/* 3. meshopt decoding                                                      */
/*                                                                          */
/* A faithful port of meshoptimizer's meshopt_decoder_reference.js (MIT,    */
/* reference decoder by Jasper St. Pierre, distributed with meshoptimizer). */
/* Bounds-checked everywhere: a truncated download returns an error.        */
/* ======================================================================== */

static uint32_t fe_dezig(uint32_t v) { return (v >> 1) ^ (uint32_t) (-(int32_t) (v & 1u)); }

int fe_meshopt_decode_vertex(uint8_t* target, size_t count, size_t stride, const uint8_t* src, size_t size) {
    if (size < 1) return -2;
    if (src[0] != 0xa0 && src[0] != 0xa1) return -1;
    const int version = src[0] & 0x0f;
    if (stride == 0 || stride > 256 || (stride % 4) != 0) return -1;

    size_t max_block = (0x2000 / stride) & ~(size_t) 0x0f;
    if (max_block > 0x100) max_block = 0x100;
    if (max_block == 0) return -1;

    const size_t tail_size = version == 0 ? stride : stride + stride / 4;
    size_t tail_padded = tail_size;
    if (tail_padded < (size_t) (version == 0 ? 32 : 24)) tail_padded = (size_t) (version == 0 ? 32 : 24);
    if (size < 1 + tail_padded) return -2;
    const size_t tail_offs = size - tail_size;
    const size_t limit = size - tail_padded; /* the data stream must end exactly here */

    uint8_t temp[256];
    memcpy(temp, src + tail_offs, stride);
    const uint8_t* channels = version == 0 ? NULL : src + tail_offs + stride;

    uint8_t* deltas = (uint8_t*) malloc(max_block * stride);
    if (!deltas) return -4;

    static const int header_modes[3][4] = {
        {0, 2, 4, 8}, /* v0 */
        {0, 1, 2, 4}, /* v1, control 0 */
        {1, 2, 4, 8}, /* v1, control 1 */
    };

    size_t s = 1; /* skip the header byte */
#define FE_NEED(n)                      \
    do {                                \
        if (s + (size_t) (n) > limit) { \
            free(deltas);               \
            return -2;                  \
        }                               \
    } while (0)

    for (size_t base = 0; base < count; base += max_block) {
        const size_t n = (count - base < max_block) ? count - base : max_block;
        const size_t group_count = ((n + 0x0f) & ~(size_t) 0x0f) >> 4;
        const size_t n_aligned = group_count << 4; /* delta row length; rows never overlap */
        const size_t header_bytes = ((group_count + 0x03) & ~(size_t) 0x03) >> 2;

        const size_t control_offs = s;
        if (version != 0) {
            FE_NEED(stride / 4);
            s += stride / 4;
        }
        memset(deltas, 0, max_block * stride);

        for (size_t byte = 0; byte < stride; byte++) {
            const size_t delta_base = byte * n_aligned;
            const int control = version == 0 ? 0 : (src[control_offs + (byte >> 2)] >> ((byte & 0x03) << 1)) & 0x03;

            if (control == 2) continue; /* all deltas zero, nothing stored */
            if (control == 3) {         /* stored verbatim, no header */
                FE_NEED(n);
                memcpy(deltas + delta_base, src + s, n);
                s += n;
                continue;
            }

            FE_NEED(header_bytes);
            const size_t header_offs = s;
            s += header_bytes;

            for (size_t g = 0; g < group_count; g++) {
                const int mode = (src[header_offs + (g >> 2)] >> ((g & 0x03) << 1)) & 0x03;
                const int bits = header_modes[version == 0 ? 0 : control + 1][mode];
                uint8_t* d = deltas + delta_base + (g << 4);

                if (bits == 0) {
                    /* all 16 deltas zero */
                } else if (bits == 1) {
                    FE_NEED(2);
                    const size_t sb = s;
                    s += 2;
                    for (int m = 0; m < 16; m++) {
                        unsigned v = (src[sb + (m >> 3)] >> (m & 0x07)) & 0x01;
                        if (v == 1) {
                            FE_NEED(1);
                            v = src[s++];
                        }
                        d[m] = (uint8_t) v;
                    }
                } else if (bits == 2) {
                    FE_NEED(4);
                    const size_t sb = s;
                    s += 4;
                    for (int m = 0; m < 16; m++) {
                        const int shift = 6 - ((m & 0x03) << 1);
                        unsigned v = (src[sb + (m >> 2)] >> shift) & 0x03;
                        if (v == 3) {
                            FE_NEED(1);
                            v = src[s++];
                        }
                        d[m] = (uint8_t) v;
                    }
                } else if (bits == 4) {
                    FE_NEED(8);
                    const size_t sb = s;
                    s += 8;
                    for (int m = 0; m < 16; m++) {
                        const int shift = 4 - ((m & 0x01) << 2);
                        unsigned v = (src[sb + (m >> 1)] >> shift) & 0x0f;
                        if (v == 0x0f) {
                            FE_NEED(1);
                            v = src[s++];
                        }
                        d[m] = (uint8_t) v;
                    }
                } else {
                    FE_NEED(16);
                    memcpy(d, src + s, 16);
                    s += 16;
                }
            }
        }

        for (size_t e = 0; e < n; e++) {
            uint8_t* out = target + (base + e) * stride;
            for (size_t bg = 0; bg < stride; bg += 4) {
                const int channel = version == 0 ? 0 : channels[bg >> 2] & 0x03;
                if (channel == 0) {
                    for (size_t b = bg; b < bg + 4; b++) {
                        const uint32_t delta = fe_dezig(deltas[b * n_aligned + e]);
                        const uint8_t v = (uint8_t) ((temp[b] + delta) & 0xff);
                        out[b] = temp[b] = v;
                    }
                } else if (channel == 1) {
                    for (size_t b = bg; b < bg + 4; b += 2) {
                        const uint32_t raw = (uint32_t) deltas[b * n_aligned + e] | ((uint32_t) deltas[(b + 1) * n_aligned + e] << 8);
                        const uint32_t delta = fe_dezig(raw);
                        uint32_t v = (uint32_t) temp[b] | ((uint32_t) temp[b + 1] << 8);
                        v = (v + delta) & 0xffff;
                        out[b] = temp[b] = (uint8_t) (v & 0xff);
                        out[b + 1] = temp[b + 1] = (uint8_t) (v >> 8);
                    }
                } else if (channel == 2) {
                    const size_t b = bg;
                    const uint32_t delta = (uint32_t) deltas[b * n_aligned + e] | ((uint32_t) deltas[(b + 1) * n_aligned + e] << 8) |
                                           ((uint32_t) deltas[(b + 2) * n_aligned + e] << 16) |
                                           ((uint32_t) deltas[(b + 3) * n_aligned + e] << 24);
                    uint32_t v = (uint32_t) temp[b] | ((uint32_t) temp[b + 1] << 8) | ((uint32_t) temp[b + 2] << 16) |
                                 ((uint32_t) temp[b + 3] << 24);
                    const unsigned rot = (unsigned) (channels[bg >> 2] >> 4) & 31u;
                    const uint32_t rotated = rot == 0 ? delta : ((delta >> rot) | (delta << (32 - rot)));
                    v ^= rotated;
                    out[b] = temp[b] = (uint8_t) (v & 0xff);
                    out[b + 1] = temp[b + 1] = (uint8_t) ((v >> 8) & 0xff);
                    out[b + 2] = temp[b + 2] = (uint8_t) ((v >> 16) & 0xff);
                    out[b + 3] = temp[b + 3] = (uint8_t) (v >> 24);
                } else {
                    free(deltas);
                    return -1; /* channel mode 3 is reserved */
                }
            }
        }
    }
#undef FE_NEED
    free(deltas);
    return s == limit ? 0 : -3;
}

static int16_t fe_round_i16(double v) {
    double r = floor(v + 0.5);
    if (r > 32767.0) r = 32767.0;
    if (r < -32768.0) r = -32768.0;
    return (int16_t) r;
}

static int8_t fe_round_i8(double v) {
    double r = floor(v + 0.5);
    if (r > 127.0) r = 127.0;
    if (r < -128.0) r = -128.0;
    return (int8_t) r;
}

int fe_meshopt_apply_filter(uint8_t* data, size_t count, size_t stride, int filter) {
    if (filter == FE_MESHOPT_FILTER_NONE) return 0;
    if (filter == FE_MESHOPT_FILTER_OCTAHEDRAL) {
        if (stride != 4 && stride != 8) return -1;
        const double max_int = stride == 4 ? 127.0 : 32767.0;
        for (size_t i = 0; i < count; i++) {
            double x, y, one;
            if (stride == 4) {
                int8_t* v = (int8_t*) (data + i * 4);
                x = v[0];
                y = v[1];
                one = v[2];
            } else {
                int16_t v[4];
                memcpy(v, data + i * 8, 8);
                x = v[0];
                y = v[1];
                one = v[2];
            }
            if (one == 0.0) one = 1.0;
            x /= one;
            y /= one;
            const double z = 1.0 - fabs(x) - fabs(y);
            const double t = z < 0.0 ? -z : 0.0;
            x -= x >= 0 ? t : -t;
            y -= y >= 0 ? t : -t;
            const double len = sqrt(x * x + y * y + z * z);
            const double h = len > 0.0 ? max_int / len : 0.0;
            if (stride == 4) {
                int8_t* v = (int8_t*) (data + i * 4);
                v[0] = fe_round_i8(x * h);
                v[1] = fe_round_i8(y * h);
                v[2] = fe_round_i8(z * h);
            } else {
                int16_t v[4];
                memcpy(v, data + i * 8, 8);
                v[0] = fe_round_i16(x * h);
                v[1] = fe_round_i16(y * h);
                v[2] = fe_round_i16(z * h);
                memcpy(data + i * 8, v, 8);
            }
        }
        return 0;
    }
    if (filter == FE_MESHOPT_FILTER_QUATERNION) {
        if (stride != 8) return -1;
        for (size_t i = 0; i < count; i++) {
            int16_t q[4];
            memcpy(q, data + i * 8, 8);
            const int input_w = q[3];
            const int max_component = input_w & 0x03;
            const double s = 0.70710678118654752440 / (double) (input_w | 0x03);
            const double x = q[0] * s, y = q[1] * s, z = q[2] * s;
            double ww = 1.0 - x * x - y * y - z * z;
            const double w = sqrt(ww > 0.0 ? ww : 0.0);
            int16_t o[4];
            o[(max_component + 1) % 4] = fe_round_i16(x * 32767.0);
            o[(max_component + 2) % 4] = fe_round_i16(y * 32767.0);
            o[(max_component + 3) % 4] = fe_round_i16(z * 32767.0);
            o[(max_component + 0) % 4] = fe_round_i16(w * 32767.0);
            memcpy(data + i * 8, o, 8);
        }
        return 0;
    }
    if (filter == FE_MESHOPT_FILTER_EXPONENTIAL) {
        if ((stride & 0x03) != 0) return -1;
        const size_t n = count * (stride / 4);
        for (size_t i = 0; i < n; i++) {
            int32_t v;
            memcpy(&v, data + i * 4, 4);
            const int32_t e = v >> 24;
            const int32_t mantissa = (int32_t) ((uint32_t) v << 8) >> 8;
            const float f = ldexpf((float) mantissa, e);
            memcpy(data + i * 4, &f, 4);
        }
        return 0;
    }
    if (filter == FE_MESHOPT_FILTER_COLOR) {
        if (stride != 4 && stride != 8) return -1;
        const double max_int = (double) ((1u << (stride * 2)) - 1u);
        for (size_t i = 0; i < count; i++) {
            double yv, co, cg, alpha_in;
            if (stride == 4) {
                uint8_t* u = data + i * 4;
                yv = u[0];
                co = (int8_t) u[1];
                cg = (int8_t) u[2];
                alpha_in = u[3];
            } else {
                uint16_t u[4];
                memcpy(u, data + i * 8, 8);
                yv = u[0];
                co = (int16_t) u[1];
                cg = (int16_t) u[2];
                alpha_in = u[3];
            }
            const uint32_t ai = (uint32_t) alpha_in;
            int alpha_bit = 31;
            while (alpha_bit >= 0 && !(ai & (1u << alpha_bit))) alpha_bit--;
            const uint32_t as = alpha_bit >= 0 ? ((1u << (alpha_bit + 1)) - 1u) : 0u;
            const double r = yv + co - cg;
            const double g = yv + cg;
            const double b = yv - co - cg;
            uint32_t a = ai & (as >> 1);
            a = (a << 1) | (a & 1u);
            const double ss = as ? max_int / (double) as : 0.0;
            const double outv[4] = {floor(r * ss + 0.5), floor(g * ss + 0.5), floor(b * ss + 0.5), floor((double) a * ss + 0.5)};
            if (stride == 4) {
                for (int k = 0; k < 4; k++) data[i * 4 + k] = (uint8_t) clampf((float) outv[k], 0.f, 255.f);
            } else {
                uint16_t o[4];
                for (int k = 0; k < 4; k++) o[k] = (uint16_t) clampf((float) outv[k], 0.f, 65535.f);
                memcpy(data + i * 8, o, 8);
            }
        }
        return 0;
    }
    return -1;
}

typedef struct fe_fifo {
    uint32_t* v;
    uint32_t mask;
    uint32_t offset;
} fe_fifo;

static uint32_t fe_fifo_read(const fe_fifo* f, uint32_t n) { return f->v[(f->offset - 1u - n) & f->mask]; }

static void fe_fifo_push(fe_fifo* f, uint32_t value) {
    f->v[f->offset] = value;
    f->offset = (f->offset + 1u) & f->mask;
}

static void fe_write_index(uint8_t* dst, size_t i, size_t index_size, uint32_t v) {
    if (index_size == 2) {
        const uint16_t s = (uint16_t) v;
        memcpy(dst + i * 2, &s, 2);
    } else {
        memcpy(dst + i * 4, &v, 4);
    }
}

typedef struct fe_leb {
    const uint8_t* src;
    size_t pos;
    size_t limit;
    int bad;
} fe_leb;

static uint32_t fe_leb_read(fe_leb* r) {
    uint32_t n = 0;
    for (unsigned shift = 0; shift < 35; shift += 7) {
        if (r->pos >= r->limit) {
            r->bad = 1;
            return 0;
        }
        const uint8_t b = r->src[r->pos++];
        n |= (uint32_t) (b & 0x7f) << shift;
        if (b < 0x80) return n;
    }
    r->bad = 1;
    return n;
}

int fe_meshopt_decode_index(uint8_t* dst, size_t count, size_t index_size, const uint8_t* src, size_t size) {
    if (index_size != 2 && index_size != 4) return -1;
    if (count % 3 != 0) return -1;
    const size_t tri_count = count / 3;
    if (size < 1 + tri_count + 16) return -2;
    if (src[0] != 0xe1) return -1;

    size_t code_offs = 1;
    const size_t codeaux_offs = size - 16;
    fe_leb data = {src, 1 + tri_count, codeaux_offs, 0};

    uint32_t edge_v[32] = {0};
    uint32_t vert_v[16] = {0};
    fe_fifo edge = {edge_v, 31u, 0u};
    fe_fifo vert = {vert_v, 15u, 0u};
    uint32_t next = 0, last = 0;
    size_t out = 0;

    for (size_t i = 0; i < tri_count; i++) {
        const uint8_t code = src[code_offs++];
        const uint32_t b0 = code >> 4, b1 = code & 0x0f;
        uint32_t a, b, c;

        if (b0 < 0x0f) {
            a = fe_fifo_read(&edge, (b0 << 1) + 0);
            b = fe_fifo_read(&edge, (b0 << 1) + 1);
            if (b1 == 0x00) {
                c = next++;
                fe_fifo_push(&vert, c);
            } else if (b1 < 0x0d) {
                c = fe_fifo_read(&vert, b1);
            } else if (b1 == 0x0d) {
                c = --last;
                fe_fifo_push(&vert, c);
            } else if (b1 == 0x0e) {
                c = ++last;
                fe_fifo_push(&vert, c);
            } else {
                const uint32_t v = fe_leb_read(&data);
                c = (last += fe_dezig(v));
                fe_fifo_push(&vert, c);
            }
            fe_fifo_push(&edge, b);
            fe_fifo_push(&edge, c);
            fe_fifo_push(&edge, c);
            fe_fifo_push(&edge, a);
        } else {
            if (b1 < 0x0e) {
                const uint8_t e = src[codeaux_offs + b1];
                const uint32_t z = e >> 4, w = e & 0x0f;
                a = next++;
                b = z == 0 ? next++ : fe_fifo_read(&vert, z - 1);
                c = w == 0 ? next++ : fe_fifo_read(&vert, w - 1);
                fe_fifo_push(&vert, a);
                if (z == 0) fe_fifo_push(&vert, b);
                if (w == 0) fe_fifo_push(&vert, c);
            } else {
                if (data.pos >= data.limit) return -2;
                const uint8_t e = src[data.pos++];
                if (e == 0) next = 0;
                const uint32_t z = e >> 4, w = e & 0x0f;
                if (b1 == 0x0e) a = next++;
                else a = (last += fe_dezig(fe_leb_read(&data)));
                if (z == 0) b = next++;
                else if (z == 0x0f) b = (last += fe_dezig(fe_leb_read(&data)));
                else b = fe_fifo_read(&vert, z - 1);
                if (w == 0) c = next++;
                else if (w == 0x0f) c = (last += fe_dezig(fe_leb_read(&data)));
                else c = fe_fifo_read(&vert, w - 1);
                fe_fifo_push(&vert, a);
                if (z == 0 || z == 0x0f) fe_fifo_push(&vert, b);
                if (w == 0 || w == 0x0f) fe_fifo_push(&vert, c);
            }
            fe_fifo_push(&edge, a);
            fe_fifo_push(&edge, b);
            fe_fifo_push(&edge, b);
            fe_fifo_push(&edge, c);
            fe_fifo_push(&edge, c);
            fe_fifo_push(&edge, a);
        }
        if (data.bad) return -2;
        fe_write_index(dst, out++, index_size, a);
        fe_write_index(dst, out++, index_size, b);
        fe_write_index(dst, out++, index_size, c);
    }
    return data.pos == data.limit ? 0 : -3;
}

int fe_meshopt_decode_sequence(uint8_t* dst, size_t count, size_t index_size, const uint8_t* src, size_t size) {
    if (index_size != 2 && index_size != 4) return -1;
    if (size < 1 + 4) return -2;
    if (src[0] != 0xd1) return -1;
    /* The encoder pads the stream with 4 zero bytes at the end. */
    fe_leb data = {src, 1, size - 4, 0};
    uint32_t last[2] = {0, 0};
    for (size_t i = 0; i < count; i++) {
        const uint32_t v = fe_leb_read(&data);
        if (data.bad) return -2;
        const uint32_t b = v & 0x01;
        last[b] += fe_dezig(v >> 1);
        fe_write_index(dst, i, index_size, last[b]);
    }
    return data.pos == data.limit ? 0 : -3;
}

/* ======================================================================== */
/* 4. GLB tile parsing                                                      */
/* ======================================================================== */

#define FE_CHUNK_TRIS 64u

struct fe_tile {
    float* pos; /* 3 per vertex, tile frame */
    uint32_t* vlocal;
    uint32_t vcount, vcap;

    uint32_t* tris; /* 3 per triangle */
    uint32_t* tri_local;
    uint32_t tcount, tcap;

    uint32_t* lines; /* 2 per segment */
    uint32_t lcount, lcap;

    float* chunk_min; /* 3 per chunk of FE_CHUNK_TRIS triangles */
    float* chunk_max;
    uint32_t chunk_count;

    float* local_min; /* 3 per local index */
    float* local_max;
    uint32_t local_count;

    int32_t* feature_ids;
    uint32_t feature_count;
    char layer[32];
    char build_id[64];

    float bmin[3], bmax[3];
};

typedef struct gl_view {
    const uint8_t* data;
    size_t size;
    size_t stride;
} gl_view;

typedef struct gl_ctx {
    const fj_node* root;
    const uint8_t* bin;
    size_t bin_size;
    size_t view_count;
    uint8_t** decoded; /* per view: meshopt-decoded bytes, or NULL */
    size_t* decoded_size;
    char* err;
    size_t err_cap;
} gl_ctx;

static int gl_view_get(gl_ctx* c, int64_t index, gl_view* out) {
    const fj_node* views = fj_get(c->root, "bufferViews");
    const fj_node* v = fj_at(views, (size_t) index);
    if (index < 0 || !v) {
        fe_err(c->err, c->err_cap, "bufferView %lld missing", (long long) index);
        return 0;
    }
    const size_t stride = (size_t) fj_i64(fj_get(v, "byteStride"), 0);
    const fj_node* mo = fj_get(fj_get(v, "extensions"), "EXT_meshopt_compression");
    if (mo) {
        if (!c->decoded[index]) {
            const int64_t buf = fj_i64(fj_get(mo, "buffer"), -1);
            const int64_t off = fj_i64(fj_get(mo, "byteOffset"), 0);
            const int64_t len = fj_i64(fj_get(mo, "byteLength"), -1);
            const int64_t mstride = fj_i64(fj_get(mo, "byteStride"), 0);
            const int64_t mcount = fj_i64(fj_get(mo, "count"), -1);
            const char* mode = fj_str(fj_get(mo, "mode"));
            const char* filter = fj_str(fj_get(mo, "filter"));
            if (buf != 0 || !c->bin || off < 0 || len < 0 || (size_t) (off + len) > c->bin_size || mstride <= 0 ||
                mstride > 256 || mcount < 0 || !mode) {
                fe_err(c->err, c->err_cap, "bufferView %lld: bad EXT_meshopt_compression", (long long) index);
                return 0;
            }
            const size_t out_size = (size_t) mcount * (size_t) mstride;
            uint8_t* dst = (uint8_t*) malloc(out_size ? out_size : 1);
            if (!dst) {
                fe_err(c->err, c->err_cap, "out of memory");
                return 0;
            }
            const uint8_t* src = c->bin + off;
            int rc;
            if (strcmp(mode, "ATTRIBUTES") == 0) {
                rc = fe_meshopt_decode_vertex(dst, (size_t) mcount, (size_t) mstride, src, (size_t) len);
                if (rc == 0 && filter && strcmp(filter, "NONE") != 0) {
                    int f = -1;
                    if (strcmp(filter, "OCTAHEDRAL") == 0) f = FE_MESHOPT_FILTER_OCTAHEDRAL;
                    else if (strcmp(filter, "QUATERNION") == 0) f = FE_MESHOPT_FILTER_QUATERNION;
                    else if (strcmp(filter, "EXPONENTIAL") == 0) f = FE_MESHOPT_FILTER_EXPONENTIAL;
                    else if (strcmp(filter, "COLOR") == 0) f = FE_MESHOPT_FILTER_COLOR;
                    rc = f < 0 ? -1 : fe_meshopt_apply_filter(dst, (size_t) mcount, (size_t) mstride, f);
                }
            } else if (strcmp(mode, "TRIANGLES") == 0) {
                rc = fe_meshopt_decode_index(dst, (size_t) mcount, (size_t) mstride, src, (size_t) len);
            } else if (strcmp(mode, "INDICES") == 0) {
                rc = fe_meshopt_decode_sequence(dst, (size_t) mcount, (size_t) mstride, src, (size_t) len);
            } else {
                rc = -1;
            }
            if (rc != 0) {
                free(dst);
                fe_err(c->err, c->err_cap, "bufferView %lld: meshopt %s decode failed (%d)", (long long) index, mode, rc);
                return 0;
            }
            c->decoded[index] = dst;
            c->decoded_size[index] = out_size;
        }
        out->data = c->decoded[index];
        out->size = c->decoded_size[index];
        out->stride = stride;
        return 1;
    }
    const int64_t buf = fj_i64(fj_get(v, "buffer"), -1);
    const int64_t off = fj_i64(fj_get(v, "byteOffset"), 0);
    const int64_t len = fj_i64(fj_get(v, "byteLength"), -1);
    if (buf != 0 || !c->bin || off < 0 || len < 0 || (size_t) (off + len) > c->bin_size) {
        fe_err(c->err, c->err_cap, "bufferView %lld: data outside the GLB BIN chunk", (long long) index);
        return 0;
    }
    out->data = c->bin + off;
    out->size = (size_t) len;
    out->stride = stride;
    return 1;
}

typedef struct gl_acc {
    const uint8_t* base;
    size_t count;
    size_t stride;
    int comp;
    int ncomp;
    int normalized;
} gl_acc;

static int gl_comp_size(int comp) {
    switch (comp) {
        case 5120:
        case 5121: return 1;
        case 5122:
        case 5123: return 2;
        case 5125:
        case 5126: return 4;
        default: return 0;
    }
}

static int gl_type_count(const char* type) {
    if (!type) return 0;
    if (strcmp(type, "SCALAR") == 0) return 1;
    if (strcmp(type, "VEC2") == 0) return 2;
    if (strcmp(type, "VEC3") == 0) return 3;
    if (strcmp(type, "VEC4") == 0) return 4;
    if (strcmp(type, "MAT4") == 0) return 16;
    return 0;
}

static int gl_acc_get(gl_ctx* c, int64_t index, gl_acc* out) {
    const fj_node* acc = fj_at(fj_get(c->root, "accessors"), (size_t) index);
    if (index < 0 || !acc) {
        fe_err(c->err, c->err_cap, "accessor %lld missing", (long long) index);
        return 0;
    }
    if (fj_get(acc, "sparse")) {
        fe_err(c->err, c->err_cap, "accessor %lld: sparse accessors are not supported", (long long) index);
        return 0;
    }
    const int comp = (int) fj_i64(fj_get(acc, "componentType"), 0);
    const int ncomp = gl_type_count(fj_str(fj_get(acc, "type")));
    const int csize = gl_comp_size(comp);
    const int64_t count = fj_i64(fj_get(acc, "count"), -1);
    const int64_t view_index = fj_i64(fj_get(acc, "bufferView"), -1);
    if (!csize || !ncomp || count < 0 || view_index < 0) {
        fe_err(c->err, c->err_cap, "accessor %lld: unsupported layout", (long long) index);
        return 0;
    }
    gl_view view;
    if (!gl_view_get(c, view_index, &view)) return 0;
    const size_t elem = (size_t) csize * (size_t) ncomp;
    const size_t stride = view.stride ? view.stride : elem;
    const int64_t offset = fj_i64(fj_get(acc, "byteOffset"), 0);
    if (offset < 0 || (count > 0 && (size_t) offset + (size_t) (count - 1) * stride + elem > view.size)) {
        fe_err(c->err, c->err_cap, "accessor %lld: out of range", (long long) index);
        return 0;
    }
    out->base = view.data + offset;
    out->count = (size_t) count;
    out->stride = stride;
    out->comp = comp;
    out->ncomp = ncomp;
    out->normalized = fj_bool(fj_get(acc, "normalized"), 0);
    return 1;
}

static double gl_read(const gl_acc* a, size_t i, int k) {
    const uint8_t* p = a->base + i * a->stride + (size_t) k * (size_t) gl_comp_size(a->comp);
    switch (a->comp) {
        case 5120: {
            int8_t v;
            memcpy(&v, p, 1);
            return a->normalized ? fmax(v / 127.0, -1.0) : (double) v;
        }
        case 5121: {
            const uint8_t v = *p;
            return a->normalized ? v / 255.0 : (double) v;
        }
        case 5122: {
            int16_t v;
            memcpy(&v, p, 2);
            return a->normalized ? fmax(v / 32767.0, -1.0) : (double) v;
        }
        case 5123: {
            uint16_t v;
            memcpy(&v, p, 2);
            return a->normalized ? v / 65535.0 : (double) v;
        }
        case 5125: {
            uint32_t v;
            memcpy(&v, p, 4);
            return (double) v;
        }
        case 5126: {
            float v;
            memcpy(&v, p, 4);
            return (double) v;
        }
        default: return 0.0;
    }
}

/* Raw integer value (the feature index is an unnormalised integer, CONTRACT
 * C7; a float accessor is rounded, a normalised one read as its raw integer). */
static uint32_t gl_read_uint(const gl_acc* a, size_t i, int k) {
    const uint8_t* p = a->base + i * a->stride + (size_t) k * (size_t) gl_comp_size(a->comp);
    switch (a->comp) {
        case 5120: {
            int8_t v;
            memcpy(&v, p, 1);
            return v < 0 ? FE_NO_FEATURE : (uint32_t) v;
        }
        case 5121: return *p;
        case 5122: {
            int16_t v;
            memcpy(&v, p, 2);
            return v < 0 ? FE_NO_FEATURE : (uint32_t) v;
        }
        case 5123: {
            uint16_t v;
            memcpy(&v, p, 2);
            return v;
        }
        case 5125: {
            uint32_t v;
            memcpy(&v, p, 4);
            return v;
        }
        case 5126: {
            float v;
            memcpy(&v, p, 4);
            if (!(v >= 0.0f) || v > 4.0e9f) return FE_NO_FEATURE;
            return (uint32_t) floorf(v + 0.5f);
        }
        default: return FE_NO_FEATURE;
    }
}

static void mat_identity(double m[16]) {
    memset(m, 0, 16 * sizeof(double));
    m[0] = m[5] = m[10] = m[15] = 1.0;
}

static void mat_mul(const double a[16], const double b[16], double out[16]) {
    double r[16];
    for (int c = 0; c < 4; c++) {
        for (int rr = 0; rr < 4; rr++) {
            double s = 0.0;
            for (int k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k];
            r[c * 4 + rr] = s;
        }
    }
    memcpy(out, r, sizeof(r));
}

static void node_local_matrix(const fj_node* node, double m[16]) {
    const fj_node* mat = fj_get(node, "matrix");
    if (fj_len(mat) == 16) {
        for (int i = 0; i < 16; i++) m[i] = fj_num(fj_at(mat, (size_t) i), (i % 5 == 0) ? 1.0 : 0.0);
        return;
    }
    double t[3] = {0, 0, 0}, s[3] = {1, 1, 1}, q[4] = {0, 0, 0, 1};
    const fj_node* tn = fj_get(node, "translation");
    const fj_node* sn = fj_get(node, "scale");
    const fj_node* rn = fj_get(node, "rotation");
    for (int i = 0; i < 3; i++) {
        t[i] = fj_num(fj_at(tn, (size_t) i), 0.0);
        s[i] = fj_num(fj_at(sn, (size_t) i), 1.0);
    }
    for (int i = 0; i < 4; i++) q[i] = fj_num(fj_at(rn, (size_t) i), i == 3 ? 1.0 : 0.0);
    const double x = q[0], y = q[1], z = q[2], w = q[3];
    const double xx = x * x, yy = y * y, zz = z * z, xy = x * y, xz = x * z, yz = y * z, wx = w * x, wy = w * y, wz = w * z;
    /* column-major rotation, each column scaled by its scale component */
    m[0] = (1 - 2 * (yy + zz)) * s[0];
    m[1] = (2 * (xy + wz)) * s[0];
    m[2] = (2 * (xz - wy)) * s[0];
    m[3] = 0;
    m[4] = (2 * (xy - wz)) * s[1];
    m[5] = (1 - 2 * (xx + zz)) * s[1];
    m[6] = (2 * (yz + wx)) * s[1];
    m[7] = 0;
    m[8] = (2 * (xz + wy)) * s[2];
    m[9] = (2 * (yz - wx)) * s[2];
    m[10] = (1 - 2 * (xx + yy)) * s[2];
    m[11] = 0;
    m[12] = t[0];
    m[13] = t[1];
    m[14] = t[2];
    m[15] = 1;
}

static int tile_reserve(void** p, uint32_t* cap, uint32_t need, size_t elem_bytes) {
    if (need <= *cap) return 1;
    uint32_t nc = *cap ? *cap : 1024;
    while (nc < need) {
        if (nc > 0x7fffffffu / 2u) return 0;
        nc *= 2;
    }
    void* np = realloc(*p, (size_t) nc * elem_bytes);
    if (!np) return 0;
    *p = np;
    *cap = nc;
    return 1;
}

/* Positions and their local indices share one capacity, as do triangles and
 * their local indices, so a single reallocation keeps each pair in step. */
static uint32_t grow_capacity(uint32_t cap, uint32_t need) {
    uint32_t nc = cap ? cap : 1024;
    while (nc < need) {
        if (nc > 0x7fffffffu / 2u) return 0;
        nc *= 2;
    }
    return nc;
}

static int tile_grow_vertices(fe_tile* t, uint32_t need) {
    if (need <= t->vcap) return 1;
    const uint32_t nc = grow_capacity(t->vcap, need);
    if (!nc) return 0;
    float* np = (float*) realloc(t->pos, (size_t) nc * 3 * sizeof(float));
    if (!np) return 0;
    t->pos = np;
    uint32_t* nl = (uint32_t*) realloc(t->vlocal, (size_t) nc * sizeof(uint32_t));
    if (!nl) return 0;
    t->vlocal = nl;
    t->vcap = nc;
    return 1;
}

static int tile_grow_triangles(fe_tile* t, uint32_t need) {
    if (need <= t->tcap) return 1;
    const uint32_t nc = grow_capacity(t->tcap, need);
    if (!nc) return 0;
    uint32_t* nt = (uint32_t*) realloc(t->tris, (size_t) nc * 3 * sizeof(uint32_t));
    if (!nt) return 0;
    t->tris = nt;
    uint32_t* nl = (uint32_t*) realloc(t->tri_local, (size_t) nc * sizeof(uint32_t));
    if (!nl) return 0;
    t->tri_local = nl;
    t->tcap = nc;
    return 1;
}

static int tile_add_primitive(gl_ctx* c, fe_tile* t, const fj_node* prim, const double world[16]) {
    const int64_t mode = fj_i64(fj_get(prim, "mode"), 4);
    if (mode != 4 && mode != 1) return 1; /* points, strips, fans: not in C7 tiles */
    const fj_node* attrs = fj_get(prim, "attributes");
    const int64_t pos_index = fj_i64(fj_get(attrs, "POSITION"), -1);
    if (pos_index < 0) return 1;
    gl_acc pos;
    if (!gl_acc_get(c, pos_index, &pos)) return 0;
    if (pos.ncomp != 3) {
        fe_err(c->err, c->err_cap, "POSITION is not VEC3");
        return 0;
    }
    gl_acc fid;
    int has_fid = 0;
    const int64_t fid_index = fj_i64(fj_get(attrs, "TEXCOORD_1"), -1);
    if (fid_index >= 0) {
        if (!gl_acc_get(c, fid_index, &fid)) return 0;
        if (fid.count != pos.count) {
            fe_err(c->err, c->err_cap, "TEXCOORD_1 count differs from POSITION");
            return 0;
        }
        has_fid = 1;
    }
    const uint32_t base = t->vcount;
    if (pos.count > 0x7fffffffu - base) {
        fe_err(c->err, c->err_cap, "too many vertices");
        return 0;
    }
    const uint32_t vneed = base + (uint32_t) pos.count;
    if (!tile_grow_vertices(t, vneed)) {
        fe_err(c->err, c->err_cap, "out of memory");
        return 0;
    }
    for (size_t i = 0; i < pos.count; i++) {
        const double x = gl_read(&pos, i, 0), y = gl_read(&pos, i, 1), z = gl_read(&pos, i, 2);
        float* o = t->pos + (size_t) (base + i) * 3;
        o[0] = (float) (world[0] * x + world[4] * y + world[8] * z + world[12]);
        o[1] = (float) (world[1] * x + world[5] * y + world[9] * z + world[13]);
        o[2] = (float) (world[2] * x + world[6] * y + world[10] * z + world[14]);
        t->vlocal[base + i] = has_fid ? gl_read_uint(&fid, i, 0) : FE_NO_FEATURE;
    }
    t->vcount = vneed;

    gl_acc idx;
    int has_idx = 0;
    const int64_t idx_index = fj_i64(fj_get(prim, "indices"), -1);
    if (idx_index >= 0) {
        if (!gl_acc_get(c, idx_index, &idx)) return 0;
        if (idx.ncomp != 1 || (idx.comp != 5121 && idx.comp != 5123 && idx.comp != 5125)) {
            fe_err(c->err, c->err_cap, "indices must be unsigned integer scalars");
            return 0;
        }
        has_idx = 1;
    }
    const size_t n = has_idx ? idx.count : pos.count;
#define FE_IDX(k) (has_idx ? gl_read_uint(&idx, (k), 0) : (uint32_t) (k))
    if (mode == 4) {
        const uint32_t add = (uint32_t) (n / 3);
        if (add > 0x7fffffffu - t->tcount || !tile_grow_triangles(t, t->tcount + add)) {
            fe_err(c->err, c->err_cap, "out of memory");
            return 0;
        }
        for (size_t k = 0; k + 2 < n; k += 3) {
            const uint32_t a = FE_IDX(k), b = FE_IDX(k + 1), cc = FE_IDX(k + 2);
            if (a >= pos.count || b >= pos.count || cc >= pos.count) {
                fe_err(c->err, c->err_cap, "index out of range");
                return 0;
            }
            uint32_t* o = t->tris + (size_t) t->tcount * 3;
            o[0] = base + a;
            o[1] = base + b;
            o[2] = base + cc;
            t->tri_local[t->tcount] = t->vlocal[base + a];
            t->tcount++;
        }
    } else {
        const uint32_t add = (uint32_t) (n / 2);
        if (!tile_reserve((void**) &t->lines, &t->lcap, t->lcount + add, 2 * sizeof(uint32_t))) {
            fe_err(c->err, c->err_cap, "out of memory");
            return 0;
        }
        for (size_t k = 0; k + 1 < n; k += 2) {
            const uint32_t a = FE_IDX(k), b = FE_IDX(k + 1);
            if (a >= pos.count || b >= pos.count) {
                fe_err(c->err, c->err_cap, "index out of range");
                return 0;
            }
            uint32_t* o = t->lines + (size_t) t->lcount * 2;
            o[0] = base + a;
            o[1] = base + b;
            t->lcount++;
        }
    }
#undef FE_IDX
    return 1;
}

static int tile_visit_node(gl_ctx* c, fe_tile* t, int64_t node_index, const double parent[16], int depth) {
    if (depth > 32) {
        fe_err(c->err, c->err_cap, "node hierarchy too deep (cycle?)");
        return 0;
    }
    const fj_node* node = fj_at(fj_get(c->root, "nodes"), (size_t) node_index);
    if (node_index < 0 || !node) {
        fe_err(c->err, c->err_cap, "node %lld missing", (long long) node_index);
        return 0;
    }
    double local[16], world[16];
    node_local_matrix(node, local);
    mat_mul(parent, local, world);
    const int64_t mesh_index = fj_i64(fj_get(node, "mesh"), -1);
    if (mesh_index >= 0) {
        const fj_node* mesh = fj_at(fj_get(c->root, "meshes"), (size_t) mesh_index);
        const fj_node* prims = fj_get(mesh, "primitives");
        for (size_t i = 0; i < fj_len(prims); i++) {
            if (!tile_add_primitive(c, t, fj_at(prims, i), world)) return 0;
        }
    }
    const fj_node* children = fj_get(node, "children");
    for (size_t i = 0; i < fj_len(children); i++) {
        if (!tile_visit_node(c, t, fj_i64(fj_at(children, i), -1), world, depth + 1)) return 0;
    }
    return 1;
}

static const fj_node* tile_find_fe(const fj_node* root, const fj_node* scene) {
    const fj_node* fe = fj_get(fj_get(scene, "extras"), "fe");
    if (fe) return fe;
    fe = fj_get(fj_get(fj_get(root, "asset"), "extras"), "fe");
    if (fe) return fe;
    fe = fj_get(fj_get(root, "extras"), "fe");
    if (fe) return fe;
    const fj_node* roots = fj_get(scene, "nodes");
    if (fj_len(roots) > 0) {
        const fj_node* n0 = fj_at(fj_get(root, "nodes"), (size_t) fj_i64(fj_at(roots, 0), -1));
        fe = fj_get(fj_get(n0, "extras"), "fe");
    }
    return fe;
}

static void tile_finish(fe_tile* t) {
    /* tile bounds */
    for (int k = 0; k < 3; k++) {
        t->bmin[k] = FLT_MAX;
        t->bmax[k] = -FLT_MAX;
    }
    for (uint32_t i = 0; i < t->vcount; i++) {
        for (int k = 0; k < 3; k++) {
            const float v = t->pos[i * 3 + k];
            if (v < t->bmin[k]) t->bmin[k] = v;
            if (v > t->bmax[k]) t->bmax[k] = v;
        }
    }
    /* chunk bounds for the ray cast */
    t->chunk_count = (t->tcount + FE_CHUNK_TRIS - 1) / FE_CHUNK_TRIS;
    if (t->chunk_count) {
        t->chunk_min = (float*) malloc((size_t) t->chunk_count * 3 * sizeof(float));
        t->chunk_max = (float*) malloc((size_t) t->chunk_count * 3 * sizeof(float));
        if (!t->chunk_min || !t->chunk_max) {
            free(t->chunk_min);
            free(t->chunk_max);
            t->chunk_min = t->chunk_max = NULL;
            t->chunk_count = 0;
        }
    }
    for (uint32_t ch = 0; ch < t->chunk_count; ch++) {
        float* mn = t->chunk_min + ch * 3;
        float* mx = t->chunk_max + ch * 3;
        mn[0] = mn[1] = mn[2] = FLT_MAX;
        mx[0] = mx[1] = mx[2] = -FLT_MAX;
        const uint32_t end = (ch + 1) * FE_CHUNK_TRIS < t->tcount ? (ch + 1) * FE_CHUNK_TRIS : t->tcount;
        for (uint32_t tr = ch * FE_CHUNK_TRIS; tr < end; tr++) {
            for (int v = 0; v < 3; v++) {
                const float* p = t->pos + (size_t) t->tris[tr * 3 + v] * 3;
                for (int k = 0; k < 3; k++) {
                    if (p[k] < mn[k]) mn[k] = p[k];
                    if (p[k] > mx[k]) mx[k] = p[k];
                }
            }
        }
    }
    /* per local index bounds */
    uint32_t max_local = 0;
    int any = 0;
    for (uint32_t i = 0; i < t->vcount; i++) {
        const uint32_t l = t->vlocal[i];
        if (l == FE_NO_FEATURE) continue;
        any = 1;
        if (l > max_local) max_local = l;
    }
    /* A garbage index stream must not trigger a giant allocation. */
    if (any && max_local < (1u << 20)) {
        t->local_count = max_local + 1;
        t->local_min = (float*) malloc((size_t) t->local_count * 3 * sizeof(float));
        t->local_max = (float*) malloc((size_t) t->local_count * 3 * sizeof(float));
        if (!t->local_min || !t->local_max) {
            free(t->local_min);
            free(t->local_max);
            t->local_min = t->local_max = NULL;
            t->local_count = 0;
        } else {
            for (uint32_t i = 0; i < t->local_count * 3; i++) {
                t->local_min[i] = FLT_MAX;
                t->local_max[i] = -FLT_MAX;
            }
            for (uint32_t i = 0; i < t->vcount; i++) {
                const uint32_t l = t->vlocal[i];
                if (l >= t->local_count) continue;
                for (int k = 0; k < 3; k++) {
                    const float v = t->pos[i * 3 + k];
                    if (v < t->local_min[l * 3 + k]) t->local_min[l * 3 + k] = v;
                    if (v > t->local_max[l * 3 + k]) t->local_max[l * 3 + k] = v;
                }
            }
        }
    }
}

fe_tile* fe_tile_parse(const uint8_t* glb, size_t size, char* err, size_t err_cap) {
    if (err && err_cap) err[0] = 0;
    if (!glb || size < 20) {
        fe_err(err, err_cap, "not a GLB (too short)");
        return NULL;
    }
    uint32_t magic, version, length;
    memcpy(&magic, glb, 4);
    memcpy(&version, glb + 4, 4);
    memcpy(&length, glb + 8, 4);
    if (magic != 0x46546C67u) {
        fe_err(err, err_cap, "not a GLB (bad magic)");
        return NULL;
    }
    if (version != 2) {
        fe_err(err, err_cap, "GLB version %u is not 2", version);
        return NULL;
    }
    if (length > size) {
        fe_err(err, err_cap, "GLB truncated (%u > %zu bytes)", length, size);
        return NULL;
    }
    size_t off = 12;
    const uint8_t* json = NULL;
    size_t json_len = 0;
    const uint8_t* bin = NULL;
    size_t bin_len = 0;
    while (off + 8 <= length) {
        uint32_t clen, ctype;
        memcpy(&clen, glb + off, 4);
        memcpy(&ctype, glb + off + 4, 4);
        off += 8;
        if (clen > length - off) {
            fe_err(err, err_cap, "GLB chunk overruns the file");
            return NULL;
        }
        if (ctype == 0x4E4F534Au && !json) {
            json = glb + off;
            json_len = clen;
        } else if (ctype == 0x004E4942u && !bin) {
            bin = glb + off;
            bin_len = clen;
        }
        off += clen;
    }
    if (!json) {
        fe_err(err, err_cap, "GLB has no JSON chunk");
        return NULL;
    }

    fj_node root;
    if (!fj_parse((const char*) json, json_len, &root)) {
        fe_err(err, err_cap, "GLB JSON is malformed");
        return NULL;
    }

    fe_tile* t = (fe_tile*) calloc(1, sizeof(fe_tile));
    gl_ctx c;
    memset(&c, 0, sizeof(c));
    c.root = &root;
    c.bin = bin;
    c.bin_size = bin_len;
    c.err = err;
    c.err_cap = err_cap;
    c.view_count = fj_len(fj_get(&root, "bufferViews"));
    c.decoded = (uint8_t**) calloc(c.view_count ? c.view_count : 1, sizeof(uint8_t*));
    c.decoded_size = (size_t*) calloc(c.view_count ? c.view_count : 1, sizeof(size_t));
    int ok = t && c.decoded && c.decoded_size;
    if (!ok) fe_err(err, err_cap, "out of memory");

    const fj_node* scenes = fj_get(&root, "scenes");
    const int64_t scene_index = fj_i64(fj_get(&root, "scene"), 0);
    const fj_node* scene = fj_at(scenes, (size_t) (scene_index < 0 ? 0 : scene_index));
    double identity[16];
    mat_identity(identity);

    if (ok) {
        if (scene) {
            const fj_node* roots = fj_get(scene, "nodes");
            for (size_t i = 0; ok && i < fj_len(roots); i++) {
                ok = tile_visit_node(&c, t, fj_i64(fj_at(roots, i), -1), identity, 0);
            }
        } else {
            /* No scene: every node that is nobody's child is a root. */
            const fj_node* nodes = fj_get(&root, "nodes");
            const size_t nn = fj_len(nodes);
            uint8_t* is_child = (uint8_t*) calloc(nn ? nn : 1, 1);
            if (!is_child) ok = 0;
            for (size_t i = 0; ok && i < nn; i++) {
                const fj_node* ch = fj_get(fj_at(nodes, i), "children");
                for (size_t k = 0; k < fj_len(ch); k++) {
                    const int64_t ci = fj_i64(fj_at(ch, k), -1);
                    if (ci >= 0 && (size_t) ci < nn) is_child[ci] = 1;
                }
            }
            for (size_t i = 0; ok && i < nn; i++) {
                if (!is_child[i]) ok = tile_visit_node(&c, t, (int64_t) i, identity, 0);
            }
            free(is_child);
        }
    }

    if (ok) {
        const fj_node* fe = tile_find_fe(&root, scene);
        const fj_node* ids = fj_get(fe, "featureIds");
        const size_t nids = fj_len(ids);
        if (nids) {
            t->feature_ids = (int32_t*) malloc(nids * sizeof(int32_t));
            if (!t->feature_ids) {
                ok = 0;
                fe_err(err, err_cap, "out of memory");
            } else {
                for (size_t i = 0; i < nids; i++) {
                    const int64_t v = fj_i64(fj_at(ids, i), -1);
                    t->feature_ids[i] = (v < 0 || v > 0x7fffffff) ? -1 : (int32_t) v;
                }
                t->feature_count = (uint32_t) nids;
            }
        }
        const char* layer = fj_str(fj_get(fe, "layer"));
        const char* build = fj_str(fj_get(fe, "buildId"));
        if (layer) snprintf(t->layer, sizeof(t->layer), "%s", layer);
        if (build) snprintf(t->build_id, sizeof(t->build_id), "%s", build);
    }

    if (ok) tile_finish(t);

    for (size_t i = 0; i < c.view_count && c.decoded; i++) free(c.decoded[i]);
    free(c.decoded);
    free(c.decoded_size);
    fj_free(&root);
    if (!ok) {
        fe_tile_free(t);
        return NULL;
    }
    return t;
}

void fe_tile_free(fe_tile* t) {
    if (!t) return;
    free(t->pos);
    free(t->vlocal);
    free(t->tris);
    free(t->tri_local);
    free(t->lines);
    free(t->chunk_min);
    free(t->chunk_max);
    free(t->local_min);
    free(t->local_max);
    free(t->feature_ids);
    free(t);
}

uint32_t fe_tile_triangle_count(const fe_tile* t) { return t ? t->tcount : 0; }
uint32_t fe_tile_line_count(const fe_tile* t) { return t ? t->lcount : 0; }
uint32_t fe_tile_feature_count(const fe_tile* t) { return t ? t->feature_count : 0; }
const int32_t* fe_tile_feature_ids(const fe_tile* t) { return t ? t->feature_ids : NULL; }
uint32_t fe_tile_local_index_count(const fe_tile* t) { return t ? t->local_count : 0; }
const char* fe_tile_layer(const fe_tile* t) { return t ? t->layer : ""; }
const char* fe_tile_build_id(const fe_tile* t) { return t ? t->build_id : ""; }

int32_t fe_tile_feature_id(const fe_tile* t, uint32_t local_index) {
    if (!t || local_index == FE_NO_FEATURE) return -1;
    if (t->feature_ids) return local_index < t->feature_count ? t->feature_ids[local_index] : -1;
    return -1;
}

int fe_tile_bounds(const fe_tile* t, float mn[3], float mx[3]) {
    if (!t || t->vcount == 0) return 0;
    memcpy(mn, t->bmin, sizeof(t->bmin));
    memcpy(mx, t->bmax, sizeof(t->bmax));
    return 1;
}

int fe_tile_local_bounds(const fe_tile* t, uint32_t l, float mn[3], float mx[3]) {
    if (!t || l >= t->local_count || !t->local_min) return 0;
    if (t->local_min[l * 3] > t->local_max[l * 3]) return 0; /* index never used */
    memcpy(mn, t->local_min + l * 3, 3 * sizeof(float));
    memcpy(mx, t->local_max + l * 3, 3 * sizeof(float));
    return 1;
}

/* ======================================================================== */
/* 5. ray casting                                                           */
/* ======================================================================== */

static int ray_box(const float o[3], const float inv[3], const float mn[3], const float mx[3], float t_max, float* t_enter) {
    float t0 = 0.0f, t1 = t_max;
    for (int k = 0; k < 3; k++) {
        float a = (mn[k] - o[k]) * inv[k];
        float b = (mx[k] - o[k]) * inv[k];
        if (a > b) {
            const float s = a;
            a = b;
            b = s;
        }
        /* NaN (0 * inf when the ray lies in a slab plane) must not reject. */
        if (a == a && a > t0) t0 = a;
        if (b == b && b < t1) t1 = b;
        if (t0 > t1) return 0;
    }
    *t_enter = t0;
    return 1;
}

int fe_tile_raycast(const fe_tile* t, const float o[3], const float d[3], float max_t, fe_hit* hit) {
    return fe_tile_raycast_masked(t, o, d, max_t, NULL, 0, hit);
}

int fe_tile_raycast_masked(const fe_tile* t, const float o[3], const float d[3], float max_t, const uint8_t* skip, uint32_t skip_count,
                           fe_hit* hit) {
    if (!t || t->tcount == 0) return 0;
    const float big = 1e30f;
    const float inv[3] = {
        fabsf(d[0]) > 1e-20f ? 1.0f / d[0] : (d[0] >= 0 ? big : -big),
        fabsf(d[1]) > 1e-20f ? 1.0f / d[1] : (d[1] >= 0 ? big : -big),
        fabsf(d[2]) > 1e-20f ? 1.0f / d[2] : (d[2] >= 0 ? big : -big),
    };
    float enter;
    if (!ray_box(o, inv, t->bmin, t->bmax, max_t, &enter)) return 0;

    float best = max_t;
    uint32_t best_tri = 0xffffffffu;
    for (uint32_t ch = 0; ch < t->chunk_count; ch++) {
        if (!ray_box(o, inv, t->chunk_min + ch * 3, t->chunk_max + ch * 3, best, &enter)) continue;
        const uint32_t end = (ch + 1) * FE_CHUNK_TRIS < t->tcount ? (ch + 1) * FE_CHUNK_TRIS : t->tcount;
        for (uint32_t tr = ch * FE_CHUNK_TRIS; tr < end; tr++) {
            const float* a = t->pos + (size_t) t->tris[tr * 3] * 3;
            const float* b = t->pos + (size_t) t->tris[tr * 3 + 1] * 3;
            const float* c = t->pos + (size_t) t->tris[tr * 3 + 2] * 3;
            /* Moller-Trumbore, double-sided */
            const float e1[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]};
            const float e2[3] = {c[0] - a[0], c[1] - a[1], c[2] - a[2]};
            const float p[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2], d[0] * e2[1] - d[1] * e2[0]};
            const float det = e1[0] * p[0] + e1[1] * p[1] + e1[2] * p[2];
            if (fabsf(det) < 1e-20f) continue;
            const float inv_det = 1.0f / det;
            const float s[3] = {o[0] - a[0], o[1] - a[1], o[2] - a[2]};
            const float u = (s[0] * p[0] + s[1] * p[1] + s[2] * p[2]) * inv_det;
            if (u < 0.0f || u > 1.0f) continue;
            const float q[3] = {s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0]};
            const float v = (d[0] * q[0] + d[1] * q[1] + d[2] * q[2]) * inv_det;
            if (v < 0.0f || u + v > 1.0f) continue;
            const float tt = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) * inv_det;
            if (tt > 1e-5f && tt < best) {
                const uint32_t l = t->tri_local[tr];
                if (skip && l < skip_count && skip[l]) continue; /* hidden feature: see through it */
                best = tt;
                best_tri = tr;
            }
        }
    }
    if (best_tri == 0xffffffffu) return 0;
    if (hit) {
        const float* a = t->pos + (size_t) t->tris[best_tri * 3] * 3;
        const float* b = t->pos + (size_t) t->tris[best_tri * 3 + 1] * 3;
        const float* c = t->pos + (size_t) t->tris[best_tri * 3 + 2] * 3;
        const float e1[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]};
        const float e2[3] = {c[0] - a[0], c[1] - a[1], c[2] - a[2]};
        float n[3] = {e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]};
        float len = sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (len > 0) {
            n[0] /= len;
            n[1] /= len;
            n[2] /= len;
        }
        if (n[0] * d[0] + n[1] * d[1] + n[2] * d[2] > 0) {
            n[0] = -n[0];
            n[1] = -n[1];
            n[2] = -n[2];
        }
        hit->t = best;
        for (int k = 0; k < 3; k++) {
            hit->point[k] = o[k] + d[k] * best;
            hit->normal[k] = n[k];
        }
        hit->local_index = t->tri_local[best_tri];
        hit->triangle = best_tri;
    }
    return 1;
}

/* ======================================================================== */
/* 6. planes and corners                                                    */
/* ======================================================================== */

/* Jacobi eigen-decomposition of a symmetric 3x3; eigenvectors in columns. */
static void jacobi3(double a[3][3], double evals[3], double v[3][3]) {
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) v[i][j] = i == j ? 1.0 : 0.0;
    for (int sweep = 0; sweep < 64; sweep++) {
        const double off = a[0][1] * a[0][1] + a[0][2] * a[0][2] + a[1][2] * a[1][2];
        if (off < 1e-30) break;
        static const int pairs[3][2] = {{0, 1}, {0, 2}, {1, 2}};
        for (int pi = 0; pi < 3; pi++) {
            const int p = pairs[pi][0], q = pairs[pi][1];
            if (fabs(a[p][q]) < 1e-300) continue;
            const double theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q]);
            const double tt = (theta >= 0 ? 1.0 : -1.0) / (fabs(theta) + sqrt(theta * theta + 1.0));
            const double c = 1.0 / sqrt(tt * tt + 1.0), s = tt * c;
            for (int k = 0; k < 3; k++) {
                const double akp = a[k][p], akq = a[k][q];
                a[k][p] = c * akp - s * akq;
                a[k][q] = s * akp + c * akq;
            }
            for (int k = 0; k < 3; k++) {
                const double apk = a[p][k], aqk = a[q][k];
                a[p][k] = c * apk - s * aqk;
                a[q][k] = s * apk + c * aqk;
            }
            for (int k = 0; k < 3; k++) {
                const double vkp = v[k][p], vkq = v[k][q];
                v[k][p] = c * vkp - s * vkq;
                v[k][q] = s * vkp + c * vkq;
            }
        }
    }
    for (int i = 0; i < 3; i++) evals[i] = a[i][i];
}

int fe_fit_plane(const float* xyz, size_t n, float centroid[3], float normal[3], float* rms) {
    if (!xyz || n < 3) return 0;
    double c[3] = {0, 0, 0};
    for (size_t i = 0; i < n; i++)
        for (int k = 0; k < 3; k++) c[k] += xyz[i * 3 + k];
    for (int k = 0; k < 3; k++) c[k] /= (double) n;
    double m[3][3] = {{0}};
    for (size_t i = 0; i < n; i++) {
        const double d[3] = {xyz[i * 3] - c[0], xyz[i * 3 + 1] - c[1], xyz[i * 3 + 2] - c[2]};
        for (int r = 0; r < 3; r++)
            for (int cc = 0; cc < 3; cc++) m[r][cc] += d[r] * d[cc];
    }
    double ev[3], vec[3][3];
    jacobi3(m, ev, vec);
    int small = 0;
    if (ev[1] < ev[small]) small = 1;
    if (ev[2] < ev[small]) small = 2;
    int large = 0;
    if (ev[1] > ev[large]) large = 1;
    if (ev[2] > ev[large]) large = 2;
    if (!(ev[large] > 1e-12)) return 0; /* all points coincide */
    double nv[3] = {vec[0][small], vec[1][small], vec[2][small]};
    const double len = sqrt(nv[0] * nv[0] + nv[1] * nv[1] + nv[2] * nv[2]);
    if (len < 1e-12) return 0;
    for (int k = 0; k < 3; k++) {
        normal[k] = (float) (nv[k] / len);
        centroid[k] = (float) c[k];
    }
    if (rms) {
        double s = 0;
        for (size_t i = 0; i < n; i++) {
            const double d = (xyz[i * 3] - c[0]) * normal[0] + (xyz[i * 3 + 1] - c[1]) * normal[1] + (xyz[i * 3 + 2] - c[2]) * normal[2];
            s += d * d;
        }
        *rms = (float) sqrt(s / (double) n);
    }
    return 1;
}

typedef struct line2 {
    double n[2]; /* unit normal, n . p = d */
    double d;
    double u[2]; /* unit direction along the line */
} line2;

static int line_from_points(const double* xz, const uint32_t* idx, size_t n, line2* out) {
    if (n < 2) return 0;
    double c[2] = {0, 0};
    for (size_t i = 0; i < n; i++) {
        c[0] += xz[idx[i] * 2];
        c[1] += xz[idx[i] * 2 + 1];
    }
    c[0] /= (double) n;
    c[1] /= (double) n;
    double sxx = 0, sxz = 0, szz = 0;
    for (size_t i = 0; i < n; i++) {
        const double dx = xz[idx[i] * 2] - c[0], dz = xz[idx[i] * 2 + 1] - c[1];
        sxx += dx * dx;
        sxz += dx * dz;
        szz += dz * dz;
    }
    const double ang = 0.5 * atan2(2.0 * sxz, sxx - szz);
    out->u[0] = cos(ang);
    out->u[1] = sin(ang);
    out->n[0] = -out->u[1];
    out->n[1] = out->u[0];
    out->d = out->n[0] * c[0] + out->n[1] * c[1];
    return 1;
}

static uint32_t lcg_next(uint32_t* s) {
    *s = *s * 1664525u + 1013904223u;
    return *s >> 8;
}

/* RANSAC for one line among the points flagged active. Returns the inlier
 * count of the refined line and fills `inl` (indices) and `ninl`. */
static size_t ransac_line(const double* xz, size_t n, const uint8_t* active, double thr, const line2* avoid, uint32_t seed,
                          line2* best_line, uint32_t* inl, size_t* ninl) {
    size_t act_n = 0;
    for (size_t i = 0; i < n; i++) act_n += active[i];
    if (act_n < 12) return 0;
    size_t best = 0;
    line2 bl;
    memset(&bl, 0, sizeof(bl));
    for (int it = 0; it < 300; it++) {
        const size_t i = lcg_next(&seed) % n, j = lcg_next(&seed) % n;
        if (i == j || !active[i] || !active[j]) continue;
        const double dx = xz[j * 2] - xz[i * 2], dz = xz[j * 2 + 1] - xz[i * 2 + 1];
        const double len = sqrt(dx * dx + dz * dz);
        if (len < 0.05) continue;
        line2 L;
        L.u[0] = dx / len;
        L.u[1] = dz / len;
        L.n[0] = -L.u[1];
        L.n[1] = L.u[0];
        L.d = L.n[0] * xz[i * 2] + L.n[1] * xz[i * 2 + 1];
        if (avoid) {
            const double cosang = fabs(L.u[0] * avoid->u[0] + L.u[1] * avoid->u[1]);
            if (cosang > 0.906) continue; /* within 25 degrees of the first face */
        }
        size_t cnt = 0;
        for (size_t k = 0; k < n; k++) {
            if (!active[k]) continue;
            if (fabs(L.n[0] * xz[k * 2] + L.n[1] * xz[k * 2 + 1] - L.d) < thr) cnt++;
        }
        if (cnt > best) {
            best = cnt;
            bl = L;
        }
    }
    if (best < 12) return 0;
    /* refine twice: least squares on the inliers, then re-collect */
    for (int pass = 0; pass < 2; pass++) {
        size_t m = 0;
        for (size_t k = 0; k < n; k++) {
            if (!active[k]) continue;
            if (fabs(bl.n[0] * xz[k * 2] + bl.n[1] * xz[k * 2 + 1] - bl.d) < thr) inl[m++] = (uint32_t) k;
        }
        if (m < 12) return 0;
        line2 R;
        if (!line_from_points(xz, inl, m, &R)) return 0;
        bl = R;
        *ninl = m;
    }
    size_t m = 0;
    for (size_t k = 0; k < n; k++) {
        if (!active[k]) continue;
        if (fabs(bl.n[0] * xz[k * 2] + bl.n[1] * xz[k * 2 + 1] - bl.d) < thr) inl[m++] = (uint32_t) k;
    }
    *ninl = m;
    *best_line = bl;
    return m;
}

static int intersect_lines(const line2* a, const line2* b, double out[2]) {
    const double det = a->n[0] * b->n[1] - a->n[1] * b->n[0];
    if (fabs(det) < 1e-6) return 0;
    out[0] = (a->d * b->n[1] - a->n[1] * b->d) / det;
    out[1] = (a->n[0] * b->d - a->d * b->n[0]) / det;
    return 1;
}

/* Shared finish: faces, kind, angle, order. dir_a/dir_b are unit vectors
 * along each face pointing away from the corner (into the wall's extent). */
static void corner_finish(const double C[2], line2 A, double dir_a[2], double span_a, line2 B, double dir_b[2], double span_b,
                          const float camera[3], const float hint[3], float floor_y, int floor_known, float rms, fe_corner* out) {
    double na[2] = {A.n[0], A.n[1]}, nb[2] = {B.n[0], B.n[1]};
    const double to_cam[2] = {camera[0] - C[0], camera[2] - C[1]};
    if (na[0] * to_cam[0] + na[1] * to_cam[1] < 0) {
        na[0] = -na[0];
        na[1] = -na[1];
    }
    if (nb[0] * to_cam[0] + nb[1] * to_cam[1] < 0) {
        nb[0] = -nb[0];
        nb[1] = -nb[1];
    }
    const int inside = (na[0] * dir_b[0] + na[1] * dir_b[1]) > 0;
    double dotab = dir_a[0] * dir_b[0] + dir_a[1] * dir_b[1];
    if (dotab > 1) dotab = 1;
    if (dotab < -1) dotab = -1;
    const double angle = acos(dotab) * 180.0 / FE_PI;
    int kind = inside ? FE_CORNER_INSIDE : FE_CORNER_OUTSIDE;
    if (!inside && span_a < 0.9 && span_b < 0.9) kind = FE_CORNER_COLUMN;
    /* deterministic order: cross(face_a, face_b) >= 0 in (x, z) */
    if (na[0] * nb[1] - na[1] * nb[0] < 0) {
        double tmp[2] = {na[0], na[1]};
        na[0] = nb[0];
        na[1] = nb[1];
        nb[0] = tmp[0];
        nb[1] = tmp[1];
        const double ts = span_a;
        span_a = span_b;
        span_b = ts;
    }
    (void) dir_a;
    out->pos[0] = (float) C[0];
    out->pos[1] = floor_known ? floor_y : hint[1];
    out->pos[2] = (float) C[1];
    out->face_a[0] = (float) na[0];
    out->face_a[1] = (float) na[1];
    out->face_b[0] = (float) nb[0];
    out->face_b[1] = (float) nb[1];
    out->angle_deg = (float) angle;
    out->kind = kind;
    out->span_a = (float) span_a;
    out->span_b = (float) span_b;
    out->rms = rms;
    const double dx = C[0] - hint[0], dz = C[1] - hint[2];
    out->dist_to_hint = (float) sqrt(dx * dx + dz * dz);
}

static int cmp_double(const void* a, const void* b) {
    const double x = *(const double*) a, y = *(const double*) b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

/* Which way along the line the face extends from the corner, and how far.
 * Rejects a line whose inliers sit substantially on both sides (a wall that
 * continues through the "corner" is a crossing, not a corner). */
static int face_extent(const double* xz, const uint32_t* inl, size_t m, const double C[2], const line2* L, double dir[2], double* span) {
    double* s = (double*) malloc(m * sizeof(double));
    if (!s) return 0;
    size_t pos = 0, neg = 0;
    for (size_t i = 0; i < m; i++) {
        const double v = (xz[inl[i] * 2] - C[0]) * L->u[0] + (xz[inl[i] * 2 + 1] - C[1]) * L->u[1];
        s[i] = v;
        if (v > 0.03) pos++;
        else if (v < -0.03) neg++;
    }
    const size_t major = pos >= neg ? pos : neg, minor = pos >= neg ? neg : pos;
    if (major < 8 || (double) minor > 0.4 * (double) (major + minor)) {
        free(s);
        return 0;
    }
    const double sign = pos >= neg ? 1.0 : -1.0;
    dir[0] = L->u[0] * sign;
    dir[1] = L->u[1] * sign;
    size_t k = 0;
    for (size_t i = 0; i < m; i++) {
        if (s[i] * sign > 0) s[k++] = s[i] * sign;
    }
    qsort(s, k, sizeof(double), cmp_double);
    *span = k ? s[(size_t) ((double) (k - 1) * 0.9)] : 0.0;
    free(s);
    return 1;
}

int fe_corner_from_points(const float* xyz, size_t n, const float hint[3], const float camera[3], float floor_y, int floor_known,
                          float noise_m, fe_corner* out) {
    if (!xyz || n < 24 || !out) return 0;
    /* Height band: around the aim point, never the floor or the ceiling. */
    double lo = hint[1] - 0.8, hi = hint[1] + 0.8;
    if (floor_known) {
        if (lo < floor_y + 0.08) lo = floor_y + 0.08;
        if (hi < lo + 0.6) hi = lo + 0.6;
        if (hi > floor_y + 2.6) hi = floor_y + 2.6;
    }
    double* xz = (double*) malloc(n * 2 * sizeof(double));
    uint8_t* active = (uint8_t*) malloc(n);
    uint32_t* inl_a = (uint32_t*) malloc(n * sizeof(uint32_t));
    uint32_t* inl_b = (uint32_t*) malloc(n * sizeof(uint32_t));
    int ok = xz && active && inl_a && inl_b;
    size_t m = 0;
    for (size_t i = 0; ok && i < n; i++) {
        const float* p = xyz + i * 3;
        if (!(p[1] >= lo && p[1] <= hi)) continue;
        const double dx = p[0] - hint[0], dz = p[2] - hint[2];
        if (dx * dx + dz * dz > 1.5 * 1.5) continue;
        xz[m * 2] = p[0];
        xz[m * 2 + 1] = p[2];
        active[m] = 1;
        m++;
    }
    if (ok && m < 24) ok = 0;
    const double thr = noise_m * 2.0 < 0.01 ? 0.01 : noise_m * 2.0;
    line2 A, B;
    size_t na = 0, nb = 0;
    if (ok) ok = ransac_line(xz, m, active, thr, NULL, 0x9e3779b9u, &A, inl_a, &na) >= 12;
    if (ok) {
        for (size_t i = 0; i < na; i++) active[inl_a[i]] = 0;
        /* also drop near-inliers so the second line isn't the first one's fringe */
        for (size_t k = 0; k < m; k++) {
            if (active[k] && fabs(A.n[0] * xz[k * 2] + A.n[1] * xz[k * 2 + 1] - A.d) < thr * 1.5) active[k] = 0;
        }
        ok = ransac_line(xz, m, active, thr, &A, 0x85ebca6bu, &B, inl_b, &nb) >= 12;
    }
    double C[2];
    if (ok) ok = intersect_lines(&A, &B, C);
    if (ok) {
        const double dx = C[0] - hint[0], dz = C[1] - hint[2];
        ok = dx * dx + dz * dz <= 0.6 * 0.6;
    }
    double dir_a[2], dir_b[2], span_a = 0, span_b = 0;
    if (ok) ok = face_extent(xz, inl_a, na, C, &A, dir_a, &span_a) && face_extent(xz, inl_b, nb, C, &B, dir_b, &span_b);
    if (ok) ok = span_a >= 0.12 && span_b >= 0.12;
    if (ok) {
        double s = 0;
        for (size_t i = 0; i < na; i++) {
            const double r = A.n[0] * xz[inl_a[i] * 2] + A.n[1] * xz[inl_a[i] * 2 + 1] - A.d;
            s += r * r;
        }
        for (size_t i = 0; i < nb; i++) {
            const double r = B.n[0] * xz[inl_b[i] * 2] + B.n[1] * xz[inl_b[i] * 2 + 1] - B.d;
            s += r * r;
        }
        const float rms = (float) sqrt(s / (double) (na + nb));
        corner_finish(C, A, dir_a, span_a, B, dir_b, span_b, camera, hint, floor_y, floor_known, rms, out);
    }
    free(xz);
    free(active);
    free(inl_a);
    free(inl_b);
    return ok;
}

int fe_corner_from_planes(const float centre_a[3], const float normal_a[3], float half_extent_a, const float centre_b[3],
                          const float normal_b[3], float half_extent_b, const float hint[3], const float camera[3], float floor_y,
                          int floor_known, fe_corner* out) {
    if (!out) return 0;
    /* both planes must be (near) vertical */
    if (fabsf(normal_a[1]) > 0.3f || fabsf(normal_b[1]) > 0.3f) return 0;
    line2 A, B;
    const float* ns[2] = {normal_a, normal_b};
    const float* cs[2] = {centre_a, centre_b};
    line2* Ls[2] = {&A, &B};
    for (int i = 0; i < 2; i++) {
        double nx = ns[i][0], nz = ns[i][2];
        const double len = sqrt(nx * nx + nz * nz);
        if (len < 1e-6) return 0;
        nx /= len;
        nz /= len;
        Ls[i]->n[0] = nx;
        Ls[i]->n[1] = nz;
        Ls[i]->u[0] = -nz;
        Ls[i]->u[1] = nx;
        Ls[i]->d = nx * cs[i][0] + nz * cs[i][2];
    }
    const double cosang = fabs(A.u[0] * B.u[0] + A.u[1] * B.u[1]);
    if (cosang > 0.906) return 0; /* closer than 25 degrees to parallel */
    double C[2];
    if (!intersect_lines(&A, &B, C)) return 0;
    const double hx = C[0] - hint[0], hz = C[1] - hint[2];
    if (hx * hx + hz * hz > 0.6 * 0.6) return 0;
    double dirs[2][2], spans[2];
    const float halves[2] = {half_extent_a, half_extent_b};
    for (int i = 0; i < 2; i++) {
        const double s = (cs[i][0] - C[0]) * Ls[i]->u[0] + (cs[i][2] - C[1]) * Ls[i]->u[1];
        if (fabs(s) < 0.1) return 0; /* the plane is centred on the corner: which side is ambiguous */
        const double sign = s > 0 ? 1.0 : -1.0;
        dirs[i][0] = Ls[i]->u[0] * sign;
        dirs[i][1] = Ls[i]->u[1] * sign;
        spans[i] = fabs(s) + halves[i];
    }
    corner_finish(C, A, dirs[0], spans[0], B, dirs[1], spans[1], camera, hint, floor_y, floor_known, 0.0f, out);
    return 1;
}

/* ======================================================================== */
/* 7. square pose                                                           */
/* ======================================================================== */

static void cross3d(const double a[3], const double b[3], double o[3]) {
    o[0] = a[1] * b[2] - a[2] * b[1];
    o[1] = a[2] * b[0] - a[0] * b[2];
    o[2] = a[0] * b[1] - a[1] * b[0];
}

static double dot3d(const double a[3], const double b[3]) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

static int norm3d(double v[3]) {
    const double l = sqrt(dot3d(v, v));
    if (l < 1e-15) return 0;
    v[0] /= l;
    v[1] /= l;
    v[2] /= l;
    return 1;
}

/* Homogeneous image point (u, v, w) -> camera-space direction. Works for
 * w = 0 (a vanishing point at infinity). Image v is down, camera +Y is up. */
static void pix_dir(double u, double v, double w, double fx, double fy, double cx, double cy, double o[3]) {
    o[0] = (u - cx * w) / fx;
    o[1] = -(v - cy * w) / fy;
    o[2] = -w;
}

int fe_square_pose(const float c[8], float fx, float fy, float cx, float cy, float edge_m, float centre_cam[3], float normal_cam[3],
                   float* distance_m) {
    if (!(fx > 0 && fy > 0 && edge_m > 0)) return 0;
    double P[4][3];
    for (int i = 0; i < 4; i++) {
        P[i][0] = c[i * 2];
        P[i][1] = c[i * 2 + 1];
        P[i][2] = 1.0;
    }
    /* vanishing points of the two edge pairs: (0-1, 3-2) and (0-3, 1-2) */
    double l01[3], l32[3], l03[3], l12[3], vp1[3], vp2[3];
    cross3d(P[0], P[1], l01);
    cross3d(P[3], P[2], l32);
    cross3d(P[0], P[3], l03);
    cross3d(P[1], P[2], l12);
    cross3d(l01, l32, vp1);
    cross3d(l03, l12, vp2);
    double d1[3], d2[3], n[3];
    pix_dir(vp1[0], vp1[1], vp1[2], fx, fy, cx, cy, d1);
    pix_dir(vp2[0], vp2[1], vp2[2], fx, fy, cx, cy, d2);
    if (!norm3d(d1) || !norm3d(d2)) return 0;
    cross3d(d1, d2, n);
    if (!norm3d(n)) return 0;
    /* centre: intersection of the diagonals */
    double l02[3], l13[3], cc[3];
    cross3d(P[0], P[2], l02);
    cross3d(P[1], P[3], l13);
    cross3d(l02, l13, cc);
    if (fabs(cc[2]) < 1e-12) return 0;
    double rc[3];
    pix_dir(cc[0] / cc[2], cc[1] / cc[2], 1.0, fx, fy, cx, cy, rc);
    if (dot3d(n, rc) > 0) {
        n[0] = -n[0];
        n[1] = -n[1];
        n[2] = -n[2];
    }
    /* plane through rc (scale 1) with normal n; intersect the corner rays */
    const double k = dot3d(n, rc);
    double X[4][3];
    for (int i = 0; i < 4; i++) {
        double r[3];
        pix_dir(P[i][0], P[i][1], 1.0, fx, fy, cx, cy, r);
        const double den = dot3d(n, r);
        if (fabs(den) < 1e-9) return 0;
        const double t = k / den;
        if (t <= 0) return 0;
        for (int j = 0; j < 3; j++) X[i][j] = r[j] * t;
    }
    double edge = 0;
    for (int i = 0; i < 4; i++) {
        const double* a = X[i];
        const double* b = X[(i + 1) & 3];
        const double dd[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]};
        edge += sqrt(dot3d(dd, dd));
    }
    edge /= 4.0;
    if (edge < 1e-12) return 0;
    const double s = edge_m / edge;
    for (int j = 0; j < 3; j++) {
        centre_cam[j] = (float) (rc[j] * s);
        normal_cam[j] = (float) n[j];
    }
    if (distance_m) *distance_m = (float) (sqrt(dot3d(rc, rc)) * s);
    return 1;
}

float fe_square_edge_on_plane(const float c[8], float fx, float fy, float cx, float cy, const float pp[3], const float pn[3]) {
    if (!(fx > 0 && fy > 0)) return -1.0f;
    const double n[3] = {pn[0], pn[1], pn[2]}, p0[3] = {pp[0], pp[1], pp[2]};
    const double k = dot3d(n, p0);
    double X[4][3];
    for (int i = 0; i < 4; i++) {
        double r[3];
        pix_dir(c[i * 2], c[i * 2 + 1], 1.0, fx, fy, cx, cy, r);
        const double den = dot3d(n, r);
        if (fabs(den) < 1e-9) return -1.0f;
        const double t = k / den;
        if (t <= 0) return -1.0f;
        for (int j = 0; j < 3; j++) X[i][j] = r[j] * t;
    }
    double edge = 0;
    for (int i = 0; i < 4; i++) {
        const double* a = X[i];
        const double* b = X[(i + 1) & 3];
        const double dd[3] = {b[0] - a[0], b[1] - a[1], b[2] - a[2]};
        edge += sqrt(dot3d(dd, dd));
    }
    return (float) (edge / 4.0);
}

/* ======================================================================== */
/* 8. overlay GLB                                                           */
/* ======================================================================== */

typedef struct sb {
    char* s;
    size_t len, cap;
    int bad;
} sb;

static void sb_put(sb* b, const char* text, size_t n) {
    if (b->bad) return;
    if (b->len + n + 1 > b->cap) {
        size_t nc = b->cap ? b->cap : 1024;
        while (b->len + n + 1 > nc) nc *= 2;
        char* ns = (char*) realloc(b->s, nc);
        if (!ns) {
            b->bad = 1;
            return;
        }
        b->s = ns;
        b->cap = nc;
    }
    memcpy(b->s + b->len, text, n);
    b->len += n;
    b->s[b->len] = 0;
}

static void sb_str(sb* b, const char* text) { sb_put(b, text, strlen(text)); }

static void sb_int(sb* b, long long v) {
    char tmp[32];
    const int n = snprintf(tmp, sizeof(tmp), "%lld", v);
    sb_put(b, tmp, (size_t) n);
}

/* Fixed six decimals, formatted by hand so the C locale can't swap '.' for ','. */
static void sb_num(sb* b, double v) {
    if (!(v == v)) v = 0;
    const int neg = v < 0;
    const double a = fabs(v);
    const long long scaled = (long long) floor(a * 1e6 + 0.5);
    const long long ip = scaled / 1000000, fp = scaled % 1000000;
    char tmp[48];
    const int n = snprintf(tmp, sizeof(tmp), "%s%lld.%06lld", (neg && scaled) ? "-" : "", ip, fp);
    sb_put(b, tmp, (size_t) n);
}

typedef struct geo {
    float* pos;
    uint32_t np, cp;
    uint32_t* idx;
    uint32_t ni, ci;
    int bad;
} geo;

static uint32_t geo_v(geo* g, float x, float y, float z) {
    if (g->bad) return 0;
    if (!tile_reserve((void**) &g->pos, &g->cp, g->np + 1, 3 * sizeof(float))) {
        g->bad = 1;
        return 0;
    }
    g->pos[g->np * 3] = x;
    g->pos[g->np * 3 + 1] = y;
    g->pos[g->np * 3 + 2] = z;
    return g->np++;
}

static void geo_i(geo* g, uint32_t i) {
    if (g->bad) return;
    if (!tile_reserve((void**) &g->idx, &g->ci, g->ni + 1, sizeof(uint32_t))) {
        g->bad = 1;
        return;
    }
    g->idx[g->ni++] = i;
}

static void geo_seg(geo* g, float x0, float y0, float z0, float x1, float y1, float z1) {
    const uint32_t a = geo_v(g, x0, y0, z0), b = geo_v(g, x1, y1, z1);
    geo_i(g, a);
    geo_i(g, b);
}

static double srgb_to_linear(double c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }

typedef struct prim_rec {
    geo g;
    int lines; /* 1 = LINES, 0 = TRIANGLES */
    uint32_t rgb;
    float alpha;
} prim_rec;

static void grid_geometry(geo* g, const fe_grid_line* L, float y) {
    const float dx = L->x1 - L->x0, dz = L->z1 - L->z0;
    const float len = sqrtf(dx * dx + dz * dz);
    if (len < 1e-3f) return;
    const float ux = dx / len, uz = dz / len;
    /* dash-dot: 0.8 dash, 0.12 gap, 0.08 dot, 0.12 gap (GAMMA's slab gridlines) */
    float t = 0.0f;
    while (t < len) {
        float e = t + 0.8f < len ? t + 0.8f : len;
        geo_seg(g, L->x0 + ux * t, y, L->z0 + uz * t, L->x0 + ux * e, y, L->z0 + uz * e);
        t = e + 0.12f;
        if (t >= len) break;
        e = t + 0.08f < len ? t + 0.08f : len;
        geo_seg(g, L->x0 + ux * t, y, L->z0 + uz * t, L->x0 + ux * e, y, L->z0 + uz * e);
        t = e + 0.12f;
    }
    /* a bubble just beyond each end */
    const float r = 0.3f;
    const float cx[2] = {L->x0 - ux * r, L->x1 + ux * r};
    const float cz[2] = {L->z0 - uz * r, L->z1 + uz * r};
    for (int e = 0; e < 2; e++) {
        for (int k = 0; k < 24; k++) {
            const float a0 = (float) (2.0 * FE_PI * k / 24.0), a1 = (float) (2.0 * FE_PI * (k + 1) / 24.0);
            geo_seg(g, cx[e] + r * cosf(a0), y, cz[e] + r * sinf(a0), cx[e] + r * cosf(a1), y, cz[e] + r * sinf(a1));
        }
    }
}

static void pin_geometry(prim_rec* tris, prim_rec* lines, const fe_pin* p) {
    if (p->shape == FE_PIN_BOARD) {
        float nx = p->normal[0], nz = p->normal[2];
        float l = sqrtf(nx * nx + nz * nz);
        if (l < 1e-6f) {
            nx = 0;
            nz = 1;
            l = 1;
        }
        nx /= l;
        nz /= l;
        /* right = up x normal, with up = +Y */
        const float rx = nz, rz = -nx;
        const float hw = 0.105f, hh = 0.1485f, off = 0.004f; /* A4 portrait, a few mm proud of the wall */
        const float cx = p->pos[0] + nx * off, cy = p->pos[1], cz = p->pos[2] + nz * off;
        const uint32_t a = geo_v(&tris->g, cx - rx * hw, cy - hh, cz - rz * hw);
        const uint32_t b = geo_v(&tris->g, cx + rx * hw, cy - hh, cz + rz * hw);
        const uint32_t c = geo_v(&tris->g, cx + rx * hw, cy + hh, cz + rz * hw);
        const uint32_t d = geo_v(&tris->g, cx - rx * hw, cy + hh, cz - rz * hw);
        geo_i(&tris->g, a);
        geo_i(&tris->g, b);
        geo_i(&tris->g, c);
        geo_i(&tris->g, a);
        geo_i(&tris->g, c);
        geo_i(&tris->g, d);
        const float ex = nx * off, ez = nz * off; /* outline a few mm in front of the fill */
        const float X[4] = {cx - rx * hw + ex, cx + rx * hw + ex, cx + rx * hw + ex, cx - rx * hw + ex};
        const float Y[4] = {cy - hh, cy - hh, cy + hh, cy + hh};
        const float Z[4] = {cz - rz * hw + ez, cz + rz * hw + ez, cz + rz * hw + ez, cz - rz * hw + ez};
        for (int k = 0; k < 4; k++) geo_seg(&lines->g, X[k], Y[k], Z[k], X[(k + 1) & 3], Y[(k + 1) & 3], Z[(k + 1) & 3]);
        /* crosshair at the registration point (the QR centre) */
        const float ch = 0.03f;
        geo_seg(&lines->g, cx + ex - rx * ch, cy, cz + ez - rz * ch, cx + ex + rx * ch, cy, cz + ez + rz * ch);
        geo_seg(&lines->g, cx + ex, cy - ch, cz + ez, cx + ex, cy + ch, cz + ez);
        return;
    }
    /* marker pin: a diamond 0.30 m above the point on a thin stem */
    const float x = p->pos[0], y = p->pos[1], z = p->pos[2];
    const float cy = y + 0.30f, h = 0.09f, r = 0.055f;
    const uint32_t top = geo_v(&tris->g, x, cy + h, z);
    const uint32_t bot = geo_v(&tris->g, x, cy - h, z);
    uint32_t ring[4];
    ring[0] = geo_v(&tris->g, x + r, cy, z);
    ring[1] = geo_v(&tris->g, x, cy, z + r);
    ring[2] = geo_v(&tris->g, x - r, cy, z);
    ring[3] = geo_v(&tris->g, x, cy, z - r);
    for (int k = 0; k < 4; k++) {
        geo_i(&tris->g, top);
        geo_i(&tris->g, ring[k]);
        geo_i(&tris->g, ring[(k + 1) & 3]);
        geo_i(&tris->g, bot);
        geo_i(&tris->g, ring[(k + 1) & 3]);
        geo_i(&tris->g, ring[k]);
    }
    geo_seg(&lines->g, x, y, z, x, cy - h, z);
    /* a small cross on the point itself */
    geo_seg(&lines->g, x - 0.05f, y, z, x + 0.05f, y, z);
    geo_seg(&lines->g, x, y, z - 0.05f, x, y, z + 0.05f);
}

uint8_t* fe_overlay_glb(const fe_grid_line* lines, size_t n_lines, float floor_y, uint32_t grid_rgb, const fe_pin* pins, size_t n_pins,
                        size_t* out_size) {
    if (out_size) *out_size = 0;
    const size_t max_prims = 1 + 2 * n_pins;
    prim_rec* prims = (prim_rec*) calloc(max_prims ? max_prims : 1, sizeof(prim_rec));
    if (!prims) return NULL;
    size_t np = 0;
    if (n_lines) {
        prim_rec* g = &prims[np++];
        g->lines = 1;
        g->rgb = grid_rgb;
        g->alpha = 0.9f;
        for (size_t i = 0; i < n_lines; i++) grid_geometry(&g->g, &lines[i], floor_y + 0.01f);
    }
    for (size_t i = 0; i < n_pins; i++) {
        prim_rec* t = &prims[np++];
        prim_rec* l = &prims[np++];
        t->lines = 0;
        l->lines = 1;
        t->rgb = l->rgb = pins[i].rgb;
        t->alpha = clampf(pins[i].alpha, 0.05f, 1.0f);
        l->alpha = 1.0f;
        pin_geometry(t, l, &pins[i]);
    }

    /* binary: per primitive, positions then indices, each 4-byte aligned */
    size_t bin_len = 0;
    int bad = 0;
    for (size_t i = 0; i < np; i++) {
        bad |= prims[i].g.bad;
        bin_len += (size_t) prims[i].g.np * 12 + (size_t) prims[i].g.ni * 4;
    }
    uint8_t* bin = (uint8_t*) malloc(bin_len ? bin_len : 4);
    sb j = {0};
    if (!bin) bad = 1;

    size_t used = 0; /* primitives with geometry */
    if (!bad) {
        sb_str(&j, "{\"asset\":{\"version\":\"2.0\",\"generator\":\"fe_ar overlay\"},");
        sb_str(&j, "\"extensionsUsed\":[\"KHR_materials_unlit\"],\"scene\":0,\"scenes\":[{\"nodes\":[0]}],");
        sb_str(&j, "\"nodes\":[{\"mesh\":0}],\"meshes\":[{\"primitives\":[");
        for (size_t i = 0; i < np; i++) {
            if (prims[i].g.np == 0 || prims[i].g.ni == 0) continue;
            const size_t acc = used * 2;
            if (used) sb_str(&j, ",");
            sb_str(&j, "{\"attributes\":{\"POSITION\":");
            sb_int(&j, (long long) acc);
            sb_str(&j, "},\"indices\":");
            sb_int(&j, (long long) acc + 1);
            sb_str(&j, ",\"material\":");
            sb_int(&j, (long long) used);
            sb_str(&j, ",\"mode\":");
            sb_int(&j, prims[i].lines ? 1 : 4);
            sb_str(&j, "}");
            used++;
        }
        sb_str(&j, "]}],\"materials\":[");
        size_t k = 0;
        for (size_t i = 0; i < np; i++) {
            if (prims[i].g.np == 0 || prims[i].g.ni == 0) continue;
            if (k++) sb_str(&j, ",");
            const uint32_t rgb = prims[i].rgb;
            sb_str(&j, "{\"pbrMetallicRoughness\":{\"baseColorFactor\":[");
            sb_num(&j, srgb_to_linear(((rgb >> 16) & 0xff) / 255.0));
            sb_str(&j, ",");
            sb_num(&j, srgb_to_linear(((rgb >> 8) & 0xff) / 255.0));
            sb_str(&j, ",");
            sb_num(&j, srgb_to_linear((rgb & 0xff) / 255.0));
            sb_str(&j, ",");
            sb_num(&j, prims[i].alpha);
            sb_str(&j, "],\"metallicFactor\":0,\"roughnessFactor\":1},\"extensions\":{\"KHR_materials_unlit\":{}},\"doubleSided\":true");
            sb_str(&j, prims[i].alpha < 0.999f ? ",\"alphaMode\":\"BLEND\"}" : "}");
        }
        sb_str(&j, "],\"accessors\":[");
        k = 0;
        size_t off = 0;
        size_t view = 0;
        for (size_t i = 0; i < np; i++) {
            const geo* g = &prims[i].g;
            if (g->np == 0 || g->ni == 0) continue;
            float mn[3] = {FLT_MAX, FLT_MAX, FLT_MAX}, mx[3] = {-FLT_MAX, -FLT_MAX, -FLT_MAX};
            for (uint32_t v = 0; v < g->np; v++) {
                for (int c = 0; c < 3; c++) {
                    if (g->pos[v * 3 + c] < mn[c]) mn[c] = g->pos[v * 3 + c];
                    if (g->pos[v * 3 + c] > mx[c]) mx[c] = g->pos[v * 3 + c];
                }
            }
            if (k++) sb_str(&j, ",");
            sb_str(&j, "{\"bufferView\":");
            sb_int(&j, (long long) view);
            sb_str(&j, ",\"componentType\":5126,\"count\":");
            sb_int(&j, g->np);
            sb_str(&j, ",\"type\":\"VEC3\",\"min\":[");
            for (int c = 0; c < 3; c++) {
                if (c) sb_str(&j, ",");
                sb_num(&j, mn[c]);
            }
            sb_str(&j, "],\"max\":[");
            for (int c = 0; c < 3; c++) {
                if (c) sb_str(&j, ",");
                sb_num(&j, mx[c]);
            }
            sb_str(&j, "]},{\"bufferView\":");
            sb_int(&j, (long long) view + 1);
            sb_str(&j, ",\"componentType\":5125,\"count\":");
            sb_int(&j, g->ni);
            sb_str(&j, ",\"type\":\"SCALAR\"}");
            memcpy(bin + off, g->pos, (size_t) g->np * 12);
            off += (size_t) g->np * 12;
            memcpy(bin + off, g->idx, (size_t) g->ni * 4);
            off += (size_t) g->ni * 4;
            view += 2;
        }
        sb_str(&j, "],\"bufferViews\":[");
        off = 0;
        k = 0;
        for (size_t i = 0; i < np; i++) {
            const geo* g = &prims[i].g;
            if (g->np == 0 || g->ni == 0) continue;
            if (k++) sb_str(&j, ",");
            sb_str(&j, "{\"buffer\":0,\"byteOffset\":");
            sb_int(&j, (long long) off);
            sb_str(&j, ",\"byteLength\":");
            sb_int(&j, (long long) g->np * 12);
            sb_str(&j, ",\"target\":34962},{\"buffer\":0,\"byteOffset\":");
            off += (size_t) g->np * 12;
            sb_int(&j, (long long) off);
            sb_str(&j, ",\"byteLength\":");
            sb_int(&j, (long long) g->ni * 4);
            sb_str(&j, ",\"target\":34963}");
            off += (size_t) g->ni * 4;
        }
        sb_str(&j, "],\"buffers\":[{\"byteLength\":");
        sb_int(&j, (long long) bin_len);
        sb_str(&j, "}]}");
    }

    uint8_t* glb = NULL;
    if (!bad && !j.bad && used > 0) {
        const size_t jlen = (j.len + 3) & ~(size_t) 3;
        const size_t blen = (bin_len + 3) & ~(size_t) 3;
        const size_t total = 12 + 8 + jlen + 8 + blen;
        glb = (uint8_t*) malloc(total);
        if (glb) {
            const uint32_t hdr[3] = {0x46546C67u, 2u, (uint32_t) total};
            memcpy(glb, hdr, 12);
            const uint32_t jh[2] = {(uint32_t) jlen, 0x4E4F534Au};
            memcpy(glb + 12, jh, 8);
            memcpy(glb + 20, j.s, j.len);
            memset(glb + 20 + j.len, ' ', jlen - j.len);
            const uint32_t bh[2] = {(uint32_t) blen, 0x004E4942u};
            memcpy(glb + 20 + jlen, bh, 8);
            memcpy(glb + 28 + jlen, bin, bin_len);
            memset(glb + 28 + jlen + bin_len, 0, blen - bin_len);
            if (out_size) *out_size = total;
        }
    }
    for (size_t i = 0; i < np; i++) {
        free(prims[i].g.pos);
        free(prims[i].g.idx);
    }
    free(prims);
    free(bin);
    free(j.s);
    return glb;
}
