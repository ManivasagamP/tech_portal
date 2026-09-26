import CryptoKit
import Foundation
import simd

/// One resident tile: the CPU pick mesh (C core, through FeArCpuTile), what
/// the tile says about itself, and the feature state gathered for it. GPU
/// objects live in FeArRenderer, keyed by `hash`. Main thread only.
/// Mirrors android/.../TileStore.kt TileEntry.
final class FeArTileEntry {
    let hash: String
    let path: String
    let cpu: FeArCpuTile
    let featureIds: [Int32]
    /// The GLB bytes, kept only until the renderer has uploaded them.
    var pendingData: Data?

    var stateBytes: Data?
    var stateHeight = 1
    var skipMask: Data?
    var countNormal = 1
    var countGhost = 0
    var countHighlight = 0
    var stateVersion = 0
    var targetLocals: [Int] = []

    init(hash: String, path: String, cpu: FeArCpuTile, data: Data) {
        self.hash = hash
        self.path = path
        self.cpu = cpu
        self.pendingData = data
        let ids = cpu.featureIds
        var list = [Int32](repeating: 0, count: ids.count / MemoryLayout<Int32>.size)
        _ = list.withUnsafeMutableBytes { ids.copyBytes(to: $0) }
        self.featureIds = list
    }

    var layer: String { cpu.layer }
    var buildId: String { cpu.buildId }
    var indexCount: Int { max(max(cpu.localIndexCount, featureIds.count), 1) }

    func featureId(at local: Int) -> Int {
        local >= 0 && local < featureIds.count ? Int(featureIds[local]) : -1
    }
}

/// Loads tiles off the main thread (read, content-hash check, decode for
/// picking) and keeps them in Dart's order. Mirrors TileStore.kt.
final class FeArTileStore {
    private let queue = DispatchQueue(label: "fe_ar.tiles", qos: .userInitiated)
    private(set) var order: [String] = []
    private(set) var tiles: [String: FeArTileEntry] = [:]
    private var inFlight = Set<String>()
    private var cancelled = Set<String>()
    var onWarning: ((String, String) -> Void)?

    var entries: [FeArTileEntry] { order.compactMap { tiles[$0] } }

    func load(
        _ refs: [(hash: String, path: String)],
        onEntry: @escaping (FeArTileEntry) -> Void,
        done: @escaping ([String], [[String: String]]) -> Void
    ) {
        var loaded: [String] = []
        var failed: [[String: String]] = []
        var remaining = refs.count
        if remaining == 0 {
            done(loaded, failed)
            return
        }
        func finishOne() {
            remaining -= 1
            if remaining == 0 { done(loaded, failed) }
        }
        for ref in refs {
            cancelled.remove(ref.hash)
            if tiles[ref.hash] != nil || inFlight.contains(ref.hash) {
                loaded.append(ref.hash)
                finishOne()
                continue
            }
            inFlight.insert(ref.hash)
            queue.async { [weak self] in
                var entry: FeArTileEntry?
                var reason = "decode failed"
                var mismatch: String?
                if let data = try? Data(contentsOf: URL(fileURLWithPath: ref.path)) {
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    if digest.lowercased() != ref.hash.lowercased() { mismatch = digest }
                    var err: NSString?
                    if let cpu = FeArCpuTile(data: data, error: &err) {
                        entry = FeArTileEntry(hash: ref.hash, path: ref.path, cpu: cpu, data: data)
                    } else {
                        reason = (err as String?) ?? reason
                    }
                } else {
                    reason = "file not found"
                }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.inFlight.remove(ref.hash)
                    if let m = mismatch { self.onWarning?("tile-hash-mismatch", "\(ref.hash) != \(m)") }
                    if let e = entry {
                        if self.cancelled.remove(ref.hash) != nil {
                            failed.append(["hash": ref.hash, "reason": "unloaded while loading"])
                        } else {
                            self.tiles[ref.hash] = e
                            self.order.append(ref.hash)
                            loaded.append(ref.hash)
                            onEntry(e)
                        }
                    } else {
                        failed.append(["hash": ref.hash, "reason": reason])
                    }
                    finishOne()
                }
            }
        }
    }

    /// Re-reads a tile's bytes (the renderer came back after being torn down).
    func readData(_ entry: FeArTileEntry, completion: @escaping (Data?) -> Void) {
        queue.async {
            let data = try? Data(contentsOf: URL(fileURLWithPath: entry.path))
            DispatchQueue.main.async { completion(data) }
        }
    }

    func unload(_ hashes: [String], onRemoved: (FeArTileEntry) -> Void) {
        for h in hashes {
            if inFlight.contains(h) { cancelled.insert(h) }
            guard let e = tiles.removeValue(forKey: h) else { continue }
            order.removeAll { $0 == h }
            onRemoved(e)
        }
    }

    func clear(onRemoved: (FeArTileEntry) -> Void) {
        unload(order, onRemoved: onRemoved)
        cancelled.formUnion(inFlight)
    }
}

/// The app's feature-state textures (lib/core/ar/feature_state.dart), per
/// build id ("" = every build without its own), and the gather into a
/// per-tile texture indexed by local feature index. Encoding shared with Dart
/// and materials/fe_feature.mat: RGB tint (0,0,0 = none), A = mode
/// round(a / 85): 0 hidden, 1 ghost, 2 normal, 3 highlight.
final class FeArFeatureStates {
    static let stateWidth = 256
    private var byBuild: [String: Data] = [:]

    func set(buildId: String?, rgba: Data) { byBuild[buildId ?? ""] = rgba }
    func clear() { byBuild.removeAll() }

    func gather(_ e: FeArTileEntry) {
        let tex = byBuild[e.buildId] ?? byBuild[""]
        let n = e.indexCount
        let h = (n + Self.stateWidth - 1) / Self.stateWidth
        var out = Data(count: Self.stateWidth * h * 4)
        var skip = Data(count: n)
        var normal = 0, ghost = 0, highlight = 0
        out.withUnsafeMutableBytes { (o: UnsafeMutableRawBufferPointer) in
            skip.withUnsafeMutableBytes { (s: UnsafeMutableRawBufferPointer) in
                let texCount = tex?.count ?? 0
                tex.withUnsafeBytesOrEmpty { (t: UnsafeRawBufferPointer) in
                    for i in 0..<n {
                        let fid = e.featureId(at: i)
                        var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 170
                        if fid >= 0, fid * 4 + 3 < texCount {
                            r = t[fid * 4]
                            g = t[fid * 4 + 1]
                            b = t[fid * 4 + 2]
                            a = t[fid * 4 + 3]
                        }
                        o[i * 4] = r
                        o[i * 4 + 1] = g
                        o[i * 4 + 2] = b
                        o[i * 4 + 3] = a
                        switch min(max((Int(a) + 42) / 85, 0), 3) {
                        case 0: s[i] = 1
                        case 1: ghost += 1
                        case 2: normal += 1
                        default: highlight += 1
                        }
                    }
                }
            }
        }
        e.stateBytes = out
        e.stateHeight = h
        e.skipMask = skip
        e.countNormal = normal
        e.countGhost = ghost
        e.countHighlight = highlight
        e.stateVersion += 1
    }
}

private extension Optional where Wrapped == Data {
    func withUnsafeBytesOrEmpty<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R {
        switch self {
        case .some(let d): return d.withUnsafeBytes(body)
        case .none: return body(UnsafeRawBufferPointer(start: nil, count: 0))
        }
    }
}
