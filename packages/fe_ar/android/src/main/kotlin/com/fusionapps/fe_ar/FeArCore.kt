package com.fusionapps.fe_ar

import java.nio.ByteBuffer

/**
 * JNI bindings for the shared C core (packages/fe_ar/src/fe_ar_core.c, built
 * by android/src/main/cpp/CMakeLists.txt). The same C is compiled into the
 * iOS pod, and it is the only part of fe_ar with unit tests that run on a
 * laptop (src/test/fe_ar_core_test.c): tile decoding for picks, corner
 * fitting, plane fitting, the square pose and the overlay GLB.
 *
 * Handles are raw pointers owned by [TileStore]; free each exactly once.
 */
internal object FeArCore {
    init {
        System.loadLibrary("fe_ar_core")
    }

    /** Parses a GLB tile held in a DIRECT buffer; 0 on failure (see [nativeLastError]). */
    @JvmStatic external fun nativeTileParse(buffer: ByteBuffer, length: Int): Long

    @JvmStatic external fun nativeLastError(): String

    @JvmStatic external fun nativeTileFree(handle: Long)

    /** [triangles, lines, localIndexCount, featureCount]. */
    @JvmStatic external fun nativeTileCounts(handle: Long): IntArray

    @JvmStatic external fun nativeTileLayer(handle: Long): String

    @JvmStatic external fun nativeTileBuildId(handle: Long): String

    @JvmStatic external fun nativeTileFeatureIds(handle: Long): IntArray

    /** out6 = [minX, minY, minZ, maxX, maxY, maxZ], tile frame. */
    @JvmStatic external fun nativeTileBounds(handle: Long, out6: FloatArray): Boolean

    @JvmStatic external fun nativeTileLocalBounds(handle: Long, local: Int, out6: FloatArray): Boolean

    /**
     * Ray in the TILE frame. Returns the hit's local feature index, -1 when the
     * triangle has none, or -2 for a miss. out7 = [t, px, py, pz, nx, ny, nz].
     * [skip] (nullable) hides local indices whose byte is non-zero.
     */
    @JvmStatic external fun nativeTileRaycast(
        handle: Long, origin: FloatArray, dir: FloatArray, maxT: Float, skip: ByteArray?, out7: FloatArray,
    ): Int

    /** out12 = [px, py, pz, faceAx, faceAz, faceBx, faceBz, angleDeg, kind, spanA, spanB, rms]. */
    @JvmStatic external fun nativeCornerFromPoints(
        xyz: FloatArray, n: Int, hint: FloatArray, camera: FloatArray, floorY: Float, floorKnown: Boolean, noiseM: Float, out12: FloatArray,
    ): Boolean

    @JvmStatic external fun nativeCornerFromPlanes(
        centreA: FloatArray, normalA: FloatArray, halfA: Float,
        centreB: FloatArray, normalB: FloatArray, halfB: Float,
        hint: FloatArray, camera: FloatArray, floorY: Float, floorKnown: Boolean, out12: FloatArray,
    ): Boolean

    /** out7 = [cx, cy, cz, nx, ny, nz, rms]. */
    @JvmStatic external fun nativeFitPlane(xyz: FloatArray, n: Int, out7: FloatArray): Boolean

    /** Camera space (+X right, +Y up, -Z forward). out7 = [cx, cy, cz, nx, ny, nz, distance]. */
    @JvmStatic external fun nativeSquarePose(
        corners8: FloatArray, fx: Float, fy: Float, cx: Float, cy: Float, edgeM: Float, out7: FloatArray,
    ): Boolean

    @JvmStatic external fun nativeSquareEdgeOnPlane(
        corners8: FloatArray, fx: Float, fy: Float, cx: Float, cy: Float, point3: FloatArray, normal3: FloatArray,
    ): Float

    /** Grid lines (x0, z0, x1, z1 each) and pins (x, y, z, nx, ny, nz, alpha, shape each) as a GLB. */
    @JvmStatic external fun nativeOverlayGlb(
        lines: FloatArray?, floorY: Float, gridRgb: Int, pins: FloatArray?, pinRgb: IntArray?,
    ): ByteArray?

    const val CORNER_INSIDE = 0
    const val CORNER_OUTSIDE = 1
    const val CORNER_COLUMN = 2
    const val PIN_MARKER = 0
    const val PIN_BOARD = 1
}
