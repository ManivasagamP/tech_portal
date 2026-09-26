package com.fusionapps.fe_ar

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Column-major 4x4 float matrices (the channel's, glTF's and Filament's
 * order; element (row r, col c) at c * 4 + r) and small vector helpers.
 *
 * The model transform is 4-DoF by contract (CONTRACT C2: yaw about +Y plus a
 * translation), which is what makes easing simple and correct: interpolate
 * the yaw along the shortest arc and the translation linearly.
 */
internal object ArMath {
    fun identity(): FloatArray = floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f)

    fun multiply(a: FloatArray, b: FloatArray): FloatArray {
        val r = FloatArray(16)
        for (c in 0 until 4) for (row in 0 until 4) {
            var s = 0f
            for (k in 0 until 4) s += a[k * 4 + row] * b[c * 4 + k]
            r[c * 4 + row] = s
        }
        return r
    }

    fun transformPoint(m: FloatArray, p: FloatArray): FloatArray = floatArrayOf(
        m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
        m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
        m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
    )

    fun transformDir(m: FloatArray, d: FloatArray): FloatArray = floatArrayOf(
        m[0] * d[0] + m[4] * d[1] + m[8] * d[2],
        m[1] * d[0] + m[5] * d[1] + m[9] * d[2],
        m[2] * d[0] + m[6] * d[1] + m[10] * d[2],
    )

    /** Inverse of a rigid transform (rotation + translation). */
    fun invertRigid(m: FloatArray): FloatArray {
        val r = FloatArray(16)
        // transpose the rotation
        for (c in 0 until 3) for (row in 0 until 3) r[c * 4 + row] = m[row * 4 + c]
        val t = floatArrayOf(m[12], m[13], m[14])
        r[12] = -(r[0] * t[0] + r[4] * t[1] + r[8] * t[2])
        r[13] = -(r[1] * t[0] + r[5] * t[1] + r[9] * t[2])
        r[14] = -(r[2] * t[0] + r[6] * t[1] + r[10] * t[2])
        r[15] = 1f
        return r
    }

    /** General 4x4 inverse (projection * view), or null when singular. */
    fun invert(m: FloatArray): FloatArray? {
        val inv = FloatArray(16)
        inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
        inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
        inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
        inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
        inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
        inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
        inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
        inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
        inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
        inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
        inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
        inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
        inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
        inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
        inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
        inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
        val det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
        if (abs(det) < 1e-12f) return null
        val k = 1f / det
        for (i in 0 until 16) inv[i] *= k
        return inv
    }

    /** True for a pure yaw-about-+Y rotation plus translation (CONTRACT C2). */
    fun isYawTranslation(m: FloatArray): Boolean {
        val eps = 1e-3f
        return abs(m[1]) < eps && abs(m[4]) < eps && abs(m[6]) < eps && abs(m[9]) < eps &&
            abs(m[5] - 1f) < eps && abs(m[0] * m[0] + m[2] * m[2] - 1f) < 2 * eps &&
            abs(m[3]) < eps && abs(m[7]) < eps && abs(m[11]) < eps && abs(m[15] - 1f) < eps
    }

    /** theta for x' = x cos + z sin, z' = -x sin + z cos (column 2 is (sin, 0, cos)). */
    fun yawOf(m: FloatArray): Float = atan2(m[8], m[0])

    fun fromYawTranslation(yaw: Float, tx: Float, ty: Float, tz: Float): FloatArray {
        val c = cos(yaw)
        val s = sin(yaw)
        return floatArrayOf(c, 0f, -s, 0f, 0f, 1f, 0f, 0f, s, 0f, c, 0f, tx, ty, tz, 1f)
    }

    fun sub(a: FloatArray, b: FloatArray) = floatArrayOf(a[0] - b[0], a[1] - b[1], a[2] - b[2])
    fun add(a: FloatArray, b: FloatArray) = floatArrayOf(a[0] + b[0], a[1] + b[1], a[2] + b[2])
    fun scale(a: FloatArray, s: Float) = floatArrayOf(a[0] * s, a[1] * s, a[2] * s)
    fun dot(a: FloatArray, b: FloatArray) = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    fun length(a: FloatArray) = sqrt(dot(a, a))
    fun distance(a: FloatArray, b: FloatArray) = length(sub(a, b))

    fun normalize(a: FloatArray): FloatArray {
        val l = length(a)
        return if (l < 1e-9f) floatArrayOf(0f, 0f, 0f) else scale(a, 1f / l)
    }

    fun clamp(v: Float, lo: Float, hi: Float) = max(lo, min(hi, v))

    /** Smoothstep ease, 0..1. */
    fun ease(t: Float): Float {
        val x = clamp(t, 0f, 1f)
        return x * x * (3f - 2f * x)
    }

    /** Wraps an angle difference into (-pi, pi]. */
    fun wrapAngle(a: Float): Float {
        var x = a
        val twoPi = (2.0 * Math.PI).toFloat()
        while (x > Math.PI) x -= twoPi
        while (x <= -Math.PI) x += twoPi
        return x
    }

    fun toDoubleList(v: FloatArray): List<Double> = v.map { it.toDouble() }

    /** sRGB byte (0..255) to linear float, for material parameters. */
    fun srgbToLinear(c: Int): Float {
        val x = c / 255.0
        val l = if (x <= 0.04045) x / 12.92 else Math.pow((x + 0.055) / 1.055, 2.4)
        return l.toFloat()
    }
}

/**
 * Tolerant readers for MethodChannel arguments. The standard codec delivers
 * ints as Int or Long and doubles as Double; lists of numbers may mix them.
 */
internal object Args {
    fun map(raw: Any?): Map<*, *> = raw as? Map<*, *> ?: emptyMap<Any, Any>()

    fun double(raw: Any?): Double? = when (raw) {
        is Number -> raw.toDouble()
        is String -> raw.toDoubleOrNull()
        else -> null
    }

    fun float(raw: Any?): Float? = double(raw)?.toFloat()

    fun int(raw: Any?): Int? = when (raw) {
        is Number -> raw.toInt()
        is String -> raw.toIntOrNull()
        else -> null
    }

    fun bool(raw: Any?): Boolean? = when (raw) {
        is Boolean -> raw
        is Number -> raw.toInt() != 0
        is String -> raw == "true"
        else -> null
    }

    fun floats(raw: Any?, n: Int): FloatArray? {
        val list = when (raw) {
            is List<*> -> raw
            is DoubleArray -> raw.toList()
            is FloatArray -> raw.toList()
            else -> return null
        }
        if (list.size < n) return null
        val out = FloatArray(n)
        for (i in 0 until n) out[i] = float(list[i]) ?: return null
        return out
    }

    fun ints(raw: Any?): IntArray? {
        val list = when (raw) {
            is List<*> -> raw
            is IntArray -> return raw
            is LongArray -> return IntArray(raw.size) { raw[it].toInt() }
            else -> return null
        }
        return IntArray(list.size) { int(list[it]) ?: -1 }
    }

    fun bytes(raw: Any?): ByteArray? = when (raw) {
        is ByteArray -> raw
        is List<*> -> ByteArray(raw.size) { (int(raw[it]) ?: 0).toByte() }
        else -> null
    }

    fun string(raw: Any?): String? = raw?.toString()
}
