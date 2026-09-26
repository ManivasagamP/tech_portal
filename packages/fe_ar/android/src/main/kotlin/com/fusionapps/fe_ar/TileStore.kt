package com.fusionapps.fe_ar

import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * One resident tile: its CPU pick mesh (a handle into the C core), what the
 * tile says about itself (layer, build, feature table), and the feature state
 * gathered for it. GPU objects live in [TileRenderer], keyed by [hash].
 *
 * Main thread only, except construction (background) — see [TileStore].
 */
internal class TileEntry(
    val hash: String,
    val path: String,
    val handle: Long,
    val layer: String,
    val buildId: String,
    val featureIds: IntArray,
    val localCount: Int,
    val triangles: Int,
    val bounds: FloatArray?,
) {
    /** Bytes of the GLB, kept only until the renderer has built the GPU copy. */
    var pendingBytes: ByteBuffer? = null

    /** Per-tile feature state gathered from the app's texture (see [FeatureStates.gather]). */
    var stateBytes: ByteBuffer? = null
    var stateHeight = 1
    var skipMask: ByteArray? = null
    var countNormal = 1
    var countGhost = 0
    var countHighlight = 0
    var stateVersion = 0

    /** Local indices of the current target's features in this tile. */
    var targetLocals: IntArray = IntArray(0)

    val indexCount: Int get() = max(max(localCount, featureIds.size), 1)

    fun featureIdAt(local: Int): Int = if (local in featureIds.indices) featureIds[local] else -1
}

/**
 * Loads tiles off the main thread: read the file into a direct buffer, check
 * its content hash (tiles are content-addressed, CONTRACT C4/C7), and decode
 * it with the C core for picking. The GPU copy is made later, on the main
 * thread, by the renderer.
 */
internal class TileStore(private val onWarning: (code: String, detail: String) -> Unit) {
    private val io: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "fe_ar-tiles").apply { isDaemon = true } }
    private val main = Handler(Looper.getMainLooper())

    /** Resident tiles, insertion ordered. Main thread only. */
    val tiles = LinkedHashMap<String, TileEntry>()

    /** Hashes unloaded while their load was in flight: dropped on arrival. */
    private val cancelled = HashSet<String>()
    private val inFlight = HashSet<String>()

    /**
     * Loads [refs] (hash to path). [onEntry] runs on the main thread for each
     * new tile as soon as it is decoded (the renderer uploads it then, so
     * focus tiles appear first when Dart sends them first); [done] runs once
     * with the per-tile result.
     */
    fun load(
        refs: List<Pair<String, String>>,
        onEntry: (TileEntry) -> Unit,
        done: (loaded: List<String>, failed: List<Map<String, String>>) -> Unit,
    ) {
        val loaded = ArrayList<String>()
        val failed = ArrayList<Map<String, String>>()
        var remaining = refs.size
        if (remaining == 0) {
            done(loaded, failed)
            return
        }
        fun finishOne() {
            remaining--
            if (remaining == 0) done(loaded, failed)
        }
        for ((hash, path) in refs) {
            cancelled.remove(hash)
            if (tiles.containsKey(hash) || inFlight.contains(hash)) {
                loaded += hash
                finishOne()
                continue
            }
            inFlight += hash
            io.execute {
                val result = runCatching { decode(hash, path) }
                main.post {
                    inFlight.remove(hash)
                    val entry = result.getOrNull()
                    when {
                        entry == null -> failed += mapOf("hash" to hash, "reason" to (result.exceptionOrNull()?.message ?: "decode failed"))
                        cancelled.remove(hash) -> {
                            FeArCore.nativeTileFree(entry.handle)
                            failed += mapOf("hash" to hash, "reason" to "unloaded while loading")
                        }
                        else -> {
                            tiles[hash] = entry
                            loaded += hash
                            onEntry(entry)
                        }
                    }
                    finishOne()
                }
            }
        }
    }

    private fun decode(hash: String, path: String): TileEntry {
        val file = File(path)
        if (!file.isFile) throw IllegalStateException("file not found")
        val bytes = RandomAccessFile(file, "r").use { raf ->
            val size = raf.length()
            if (size <= 0 || size > Int.MAX_VALUE) throw IllegalStateException("bad file size $size")
            val buf = ByteBuffer.allocateDirect(size.toInt())
            val ch = raf.channel
            while (buf.hasRemaining()) {
                if (ch.read(buf) < 0) break
            }
            buf.flip()
            buf
        }
        val digest = sha256Hex(bytes)
        if (!digest.equals(hash, ignoreCase = true)) {
            // Not fatal: the parser rejects a damaged tile on its own. Reported
            // so a hashing mismatch between server and app is visible early.
            main.post { onWarning("tile-hash-mismatch", "$hash != $digest") }
        }
        val handle = FeArCore.nativeTileParse(bytes, bytes.limit())
        if (handle == 0L) throw IllegalStateException(FeArCore.nativeLastError().ifEmpty { "parse failed" })
        val counts = FeArCore.nativeTileCounts(handle)
        val bounds = FloatArray(6)
        val entry = TileEntry(
            hash = hash,
            path = path,
            handle = handle,
            layer = FeArCore.nativeTileLayer(handle),
            buildId = FeArCore.nativeTileBuildId(handle),
            featureIds = FeArCore.nativeTileFeatureIds(handle),
            localCount = counts[2],
            triangles = counts[0],
            bounds = if (FeArCore.nativeTileBounds(handle, bounds)) bounds else null,
        )
        entry.pendingBytes = bytes
        return entry
    }

    /** Re-reads a tile's bytes (the renderer came back after being torn down). */
    fun readBytes(entry: TileEntry, callback: (ByteBuffer?) -> Unit) {
        io.execute {
            val bytes = runCatching {
                RandomAccessFile(File(entry.path), "r").use { raf ->
                    val buf = ByteBuffer.allocateDirect(raf.length().toInt())
                    while (buf.hasRemaining()) {
                        if (raf.channel.read(buf) < 0) break
                    }
                    buf.flip()
                    buf
                }
            }.getOrNull()
            main.post { callback(bytes) }
        }
    }

    fun unload(hashes: Collection<String>, onRemoved: (TileEntry) -> Unit) {
        for (h in hashes) {
            if (inFlight.contains(h)) cancelled += h
            val e = tiles.remove(h) ?: continue
            onRemoved(e)
            FeArCore.nativeTileFree(e.handle)
        }
    }

    fun clear(onRemoved: (TileEntry) -> Unit) {
        unload(tiles.keys.toList(), onRemoved)
        cancelled.addAll(inFlight)
    }

    fun shutdown() {
        io.shutdownNow()
    }

    private fun sha256Hex(buf: ByteBuffer): String {
        val md = MessageDigest.getInstance("SHA-256")
        val dup = buf.duplicate()
        dup.position(0)
        md.update(dup)
        return md.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}

/**
 * The app's feature-state textures (lib/core/ar/feature_state.dart), one per
 * build id ("" = applies to every build without its own), and the gather
 * that turns one into a small per-tile texture indexed by the tile-local
 * feature index.
 *
 * Encoding (shared with Dart and materials/fe_feature.mat): RGB tint (0,0,0 =
 * none), A = display mode round(a / 85): 0 hidden, 1 ghost, 2 normal,
 * 3 highlight.
 */
internal class FeatureStates {
    class Texture(val rgba: ByteArray, val width: Int)

    private val byBuild = HashMap<String, Texture>()

    fun set(buildId: String?, tex: Texture) {
        byBuild[buildId ?: ""] = tex
    }

    fun clear() = byBuild.clear()

    fun forBuild(buildId: String): Texture? = byBuild[buildId] ?: byBuild[""]

    fun gather(entry: TileEntry) {
        val tex = forBuild(entry.buildId)
        val n = entry.indexCount
        val h = (n + STATE_WIDTH - 1) / STATE_WIDTH
        val buf = ByteBuffer.allocateDirect(STATE_WIDTH * h * 4)
        val skip = ByteArray(n)
        var normal = 0
        var ghost = 0
        var highlight = 0
        for (i in 0 until n) {
            val fid = entry.featureIdAt(i)
            var r = 0
            var g = 0
            var b = 0
            var a = 170
            if (tex != null && fid >= 0) {
                val o = fid.toLong() * 4
                if (o + 3 < tex.rgba.size) {
                    val k = o.toInt()
                    r = tex.rgba[k].toInt() and 0xff
                    g = tex.rgba[k + 1].toInt() and 0xff
                    b = tex.rgba[k + 2].toInt() and 0xff
                    a = tex.rgba[k + 3].toInt() and 0xff
                }
            }
            buf.put(i * 4, r.toByte())
            buf.put(i * 4 + 1, g.toByte())
            buf.put(i * 4 + 2, b.toByte())
            buf.put(i * 4 + 3, a.toByte())
            when (((a + 42) / 85).coerceIn(0, 3)) {
                0 -> skip[i] = 1
                1 -> ghost++
                2 -> normal++
                else -> highlight++
            }
        }
        entry.stateBytes = buf
        entry.stateHeight = h
        entry.skipMask = skip
        entry.countNormal = normal
        entry.countGhost = ghost
        entry.countHighlight = highlight
        entry.stateVersion++
    }

    companion object {
        /** Per-tile state texture width: 256 texels a row, height grows with the tile's features. */
        const val STATE_WIDTH = 256
    }
}
