import ARKit
import Vision

/// Marker observations (docs/ar-bim-overlay.md §4.2), iPhone and iPad.
/// Same pipeline as android/.../MarkerDetector.kt:
///
/// 1. Vision reads QR codes from ARKit's captured image: about 5 Hz idle,
///    then back to back while a code is being locked (~15 samples a second).
/// 2. Each sample casts a ray through the QR centre from the camera pose OF
///    THE FRAME THE CODE WAS READ IN and measures the wall:
///    LiDAR scene depth, a plane fitted to the depth under the QR ("lidar",
///    works on plain painted walls); else a tracked vertical plane
///    ("plane"); else ARKit's estimated plane ("depth"); else the square's
///    own pose from its corners ("pnp", flagged, assumes the A4 board's
///    115 mm QR).
/// 3. Gates: tracking normal, 0.5-2.0 m (3.0 m for an A3 board), within 35
///    degrees of square-on.
/// 4. After 15 samples: per-axis median, normalised mean normal, RMS spread;
///    over 15 mm -> `marker-unstable` ("hold still"); else an ARAnchor at the
///    median and one `marker` event; the payload cools down for 4 s.
final class FeArMarkerDetector {
    private struct Snapshot {
        let cameraTransform: simd_float4x4
        let fx: Float, fy: Float, cx: Float, cy: Float
        let imageWidth: Float, imageHeight: Float
        let depth: CVPixelBuffer?
        let confidence: CVPixelBuffer?
    }

    private struct Detection {
        let payload: String
        let corners: [Float] // 8: clockwise from top-left, image pixels
        let snapshot: Snapshot
    }

    private struct Sample {
        let at: CFTimeInterval
        let centre: SIMD3<Float>
        let normal: SIMD3<Float>
        let method: String
        let distance: Float
        let viewAngle: Float
        let qrEdgeMm: Float?
    }

    private struct Tracked {
        let anchor: ARAnchor
        var last: SIMD3<Float>
    }

    static let samplesNeeded = 15
    static let maxSpreadMm: Float = 15
    static let idleInterval: CFTimeInterval = 0.2
    static let sampleTtl: CFTimeInterval = 2.5
    static let cooldown: CFTimeInterval = 4
    static let qrEdgeA4M: Float = 0.115

    private let emit: ([String: Any]) -> Void
    private let queue = DispatchQueue(label: "fe_ar.vision", qos: .userInitiated)
    private var inFlight = false
    private var lastRun: CFTimeInterval = 0
    private var pending: [Detection] = []
    private var samples: [String: [Sample]] = [:]
    private var cooldownUntil: [String: CFTimeInterval] = [:]
    private var tracked: [UUID: Tracked] = [:]
    private var lastAnchorCheck: CFTimeInterval = 0
    var progressEvents = false

    init(emit: @escaping ([String: Any]) -> Void) {
        self.emit = emit
    }

    func onFrame(session: ARSession, frame: ARFrame, tracking: Bool) {
        let now = CACurrentMediaTime()
        if tracking, !pending.isEmpty {
            let batch = pending
            pending.removeAll()
            for d in batch { process(session: session, d, now: now) }
        }
        expire(now)
        if tracking { schedule(frame, now: now) }
    }

    private func schedule(_ frame: ARFrame, now: CFTimeInterval) {
        let locking = samples.values.contains { !$0.isEmpty }
        if inFlight || now - lastRun < (locking ? 0 : Self.idleInterval) { return }
        let cam = frame.camera
        let k = cam.intrinsics
        let depth = frame.smoothedSceneDepth ?? frame.sceneDepth
        let snapshot = Snapshot(
            cameraTransform: cam.transform,
            fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y,
            imageWidth: Float(cam.imageResolution.width), imageHeight: Float(cam.imageResolution.height),
            depth: depth?.depthMap, confidence: depth?.confidenceMap
        )
        let image = frame.capturedImage // retained only while Vision runs; never the ARFrame itself
        lastRun = now
        inFlight = true
        queue.async { [weak self] in
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:])
            var found: [Detection] = []
            if (try? handler.perform([request])) != nil {
                for obs in request.results ?? [] {
                    guard let payload = obs.payloadStringValue else { continue }
                    // Vision: normalised, origin bottom-left. To image pixels, v down.
                    // TODO(slice-0): confirm with orientation .up on the raw landscape buffer.
                    let w = snapshot.imageWidth, h = snapshot.imageHeight
                    let pts = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
                    var corners: [Float] = []
                    for p in pts {
                        corners.append(Float(p.x) * w)
                        corners.append((1 - Float(p.y)) * h)
                    }
                    found.append(Detection(payload: payload, corners: corners, snapshot: snapshot))
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending.append(contentsOf: found)
                self.inFlight = false
            }
        }
    }

    private func process(session: ARSession, _ d: Detection, now: CFTimeInterval) {
        if (cooldownUntil[d.payload] ?? 0) > now { return }
        let s = d.snapshot
        guard let centrePx = Self.diagonalCentre(d.corners) else { return }
        let dirCam = SIMD3<Float>((centrePx.x - s.cx) / s.fx, -(centrePx.y - s.cy) / s.fy, -1)
        let origin = SIMD3<Float>(s.cameraTransform.columns.3.x, s.cameraTransform.columns.3.y, s.cameraTransform.columns.3.z)
        let dirWorld = simd_normalize(Self.rotate(s.cameraTransform, dirCam))

        var centre: SIMD3<Float>?
        var normal: SIMD3<Float>?
        var method = "pnp"
        var qrEdgeMm: Float?

        // 1) LiDAR: a plane fitted to the measured depth under the QR
        if let plane = lidarPlane(s, corners: d.corners, dirCam: dirCam) {
            let (cCam, nCam) = plane
            centre = Self.transform(s.cameraTransform, cCam)
            normal = Self.rotate(s.cameraTransform, nCam)
            method = "lidar"
            let e = d.corners.withUnsafeBufferPointer {
                FeArGeometry.squareEdgeCorners($0.baseAddress!, fx: s.fx, fy: s.fy, cx: s.cx, cy: s.cy, planePoint: cCam, planeNormal: nCam)
            }
            if e > 0 { qrEdgeMm = e * 1000 }
        }
        // 2) a tracked vertical plane, 3) ARKit's estimated plane
        if centre == nil {
            for (target, label) in [(ARRaycastQuery.Target.existingPlaneGeometry, "plane"), (.estimatedPlane, "depth")] {
                let q = ARRaycastQuery(origin: origin, direction: dirWorld, allowing: target, alignment: .vertical)
                if let r = session.raycast(q).first {
                    let t = r.worldTransform
                    centre = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                    normal = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
                    method = label
                    break
                }
            }
        }
        // 4) the square's own pose
        if centre == nil {
            var cCam = SIMD3<Float>(repeating: 0), nCam = SIMD3<Float>(repeating: 0)
            var dist: Float = 0
            let ok = d.corners.withUnsafeBufferPointer {
                FeArGeometry.squarePoseCorners($0.baseAddress!, fx: s.fx, fy: s.fy, cx: s.cx, cy: s.cy, edgeM: Self.qrEdgeA4M,
                                               centre: &cCam, normal: &nCam, distance: &dist)
            }
            guard ok else { return }
            centre = Self.transform(s.cameraTransform, cCam)
            normal = Self.rotate(s.cameraTransform, nCam)
            method = "pnp"
        }
        guard let c = centre, var n = normal.map({ simd_normalize($0) }) else { return }
        let toCam = origin - c
        if simd_dot(n, toCam) < 0 { n = -n }
        let distance = simd_length(toCam)
        let viewAngle = acos(max(-1, min(1, simd_dot(n, simd_normalize(toCam))))) * 180 / .pi

        let maxDistance: Float = (qrEdgeMm ?? 0) >= 150 ? 3.0 : 2.0
        let gate: String?
        if distance < 0.5 { gate = "tooClose" } else if distance > maxDistance { gate = "tooFar" } else if viewAngle > 35 { gate = "angle" } else { gate = nil }

        var list = samples[d.payload] ?? []
        if gate == nil {
            list.append(Sample(at: now, centre: c, normal: n, method: method, distance: distance, viewAngle: viewAngle, qrEdgeMm: qrEdgeMm))
            if list.count > 30 { list.removeFirst(list.count - 30) }
        }
        samples[d.payload] = list
        if progressEvents {
            emit([
                "type": "markerProgress", "rawPayload": d.payload, "samples": list.count, "needed": Self.samplesNeeded,
                "distanceM": Double(distance), "viewAngleDeg": Double(viewAngle), "gate": gate ?? "ok",
            ])
        }
        if list.count >= Self.samplesNeeded { finish(session: session, payload: d.payload, list: list, now: now) }
    }

    private func finish(session: ARSession, payload: String, list: [Sample], now: CFTimeInterval) {
        let centre = SIMD3<Float>(Self.median(list.map { $0.centre.x }), Self.median(list.map { $0.centre.y }), Self.median(list.map { $0.centre.z }))
        let normal = simd_normalize(list.reduce(SIMD3<Float>(repeating: 0)) { $0 + $1.normal })
        let sq = list.reduce(Float(0)) { acc, s in acc + simd_length_squared(s.centre - centre) }
        let spreadMm = (sq / Float(list.count)).squareRoot() * 1000
        if spreadMm > Self.maxSpreadMm {
            emit(["type": "error", "code": "marker-unstable", "detail": String(format: "%@ spread %.1f mm: hold still", payload, spreadMm)])
            samples[payload] = Array(list.suffix(list.count - list.count / 2))
            return
        }
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4<Float>(centre.x, centre.y, centre.z, 1)
        let anchor = ARAnchor(name: "fe-marker", transform: t)
        session.add(anchor: anchor)
        tracked[anchor.identifier] = Tracked(anchor: anchor, last: centre)
        let method = list.contains { $0.method == "pnp" } ? "pnp"
            : list.contains { $0.method == "depth" } ? "depth"
            : list.contains { $0.method == "plane" } ? "plane" : "lidar"
        let edges = list.compactMap { $0.qrEdgeMm }
        emit([
            "type": "marker",
            "rawPayload": payload,
            "anchorId": anchor.identifier.uuidString,
            "centreAr": [Double(centre.x), Double(centre.y), Double(centre.z)],
            "normalAr": [Double(normal.x), Double(normal.y), Double(normal.z)],
            "method": method,
            "spreadMm": Double(spreadMm),
            "distanceM": Double(Self.median(list.map { $0.distance })),
            "viewAngleDeg": Double(Self.median(list.map { $0.viewAngle })),
            "qrEdgeMm": edges.count >= list.count / 2 ? Double(Self.median(edges)) as Any : NSNull(),
        ])
        samples[payload] = nil
        cooldownUntil[payload] = now + Self.cooldown
    }

    /// ARKit refined our anchors: report moves over 1 mm, at most 2 Hz.
    func anchorsUpdated(_ anchors: [ARAnchor]) {
        let now = CACurrentMediaTime()
        if now - lastAnchorCheck < 0.5 { return }
        lastAnchorCheck = now
        for a in anchors {
            guard var t = tracked[a.identifier] else { continue }
            let p = SIMD3<Float>(a.transform.columns.3.x, a.transform.columns.3.y, a.transform.columns.3.z)
            if simd_distance(p, t.last) > 0.001 {
                t.last = p
                tracked[a.identifier] = t
                emit(["type": "anchor", "anchorId": a.identifier.uuidString, "posAr": [Double(p.x), Double(p.y), Double(p.z)]])
            }
        }
    }

    func anchorsRemoved(_ anchors: [ARAnchor]) {
        for a in anchors { tracked[a.identifier] = nil }
    }

    func reset(session: ARSession?) {
        if let s = session { for t in tracked.values { s.remove(anchor: t.anchor) } }
        tracked.removeAll()
        samples.removeAll()
        pending.removeAll()
        cooldownUntil.removeAll()
    }

    private func expire(_ now: CFTimeInterval) {
        for (k, v) in samples {
            let kept = v.filter { now - $0.at <= Self.sampleTtl }
            samples[k] = kept.isEmpty ? nil : kept
        }
    }

    // MARK: LiDAR

    /// Plane under the QR from scene depth, camera space: (centre on the
    /// centre ray, normal). Nil without depth, with too few confident samples,
    /// or when the patch isn't flat (RMS over 1 cm).
    private func lidarPlane(_ s: Snapshot, corners: [Float], dirCam: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>)? {
        guard let depth = s.depth else { return nil }
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        if let conf = s.confidence { CVPixelBufferLockBaseAddress(conf, .readOnly) }
        defer { if let conf = s.confidence { CVPixelBufferUnlockBaseAddress(conf, .readOnly) } }
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let dw = CVPixelBufferGetWidth(depth), dh = CVPixelBufferGetHeight(depth)
        let rowFloats = CVPixelBufferGetBytesPerRow(depth) / MemoryLayout<Float32>.size
        let depths = base.assumingMemoryBound(to: Float32.self)
        let confBase = s.confidence.flatMap { CVPixelBufferGetBaseAddress($0) }?.assumingMemoryBound(to: UInt8.self)
        let confRow = s.confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        let sx = Float(dw) / s.imageWidth, sy = Float(dh) / s.imageHeight

        // the QR's bounding box in depth pixels, inset 15% to stay on the board
        let xs = stride(from: 0, to: 8, by: 2).map { corners[$0] * sx }
        let ys = stride(from: 1, to: 8, by: 2).map { corners[$0] * sy }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let ix = (x1 - x0) * 0.15, iy = (y1 - y0) * 0.15
        let u0 = max(0, Int(x0 + ix)), u1 = min(dw - 1, Int(x1 - ix))
        let v0 = max(0, Int(y0 + iy)), v1 = min(dh - 1, Int(y1 - iy))
        guard u1 >= u0, v1 >= v0 else { return nil }
        var pts: [Float] = []
        for v in v0...v1 {
            for u in u0...u1 {
                if let cb = confBase, cb[v * confRow + u] < UInt8(ARConfidenceLevel.medium.rawValue) { continue }
                let z = depths[v * rowFloats + u]
                guard z.isFinite, z > 0.2, z < 5 else { continue }
                let px = (Float(u) + 0.5) / sx, py = (Float(v) + 0.5) / sy // back to image pixels
                pts.append((px - s.cx) / s.fx * z)
                pts.append(-(py - s.cy) / s.fy * z)
                pts.append(-z)
            }
        }
        guard pts.count >= 3 * 8 else { return nil }
        var centroid = SIMD3<Float>(repeating: 0), n = SIMD3<Float>(repeating: 0)
        var rms: Float = 0
        let data = pts.withUnsafeBufferPointer { Data(buffer: $0) }
        guard FeArGeometry.fitPlane(data, centroid: &centroid, normal: &n, rms: &rms), rms < 0.01 else { return nil }
        let den = simd_dot(n, dirCam)
        guard abs(den) > 1e-4 else { return nil }
        let t = simd_dot(n, centroid) / den
        guard t > 0 else { return nil }
        return (dirCam * t, n)
    }

    // MARK: helpers

    static func transform(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = m * SIMD4<Float>(p.x, p.y, p.z, 1)
        return SIMD3<Float>(r.x, r.y, r.z)
    }

    static func rotate(_ m: simd_float4x4, _ d: SIMD3<Float>) -> SIMD3<Float> {
        let r = m * SIMD4<Float>(d.x, d.y, d.z, 0)
        return SIMD3<Float>(r.x, r.y, r.z)
    }

    static func median(_ v: [Float]) -> Float {
        if v.isEmpty { return 0 }
        let s = v.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    /// Intersection of the diagonals (0-2, 1-3).
    static func diagonalCentre(_ c: [Float]) -> SIMD2<Float>? {
        let x1 = c[0], y1 = c[1], x2 = c[4], y2 = c[5], x3 = c[2], y3 = c[3], x4 = c[6], y4 = c[7]
        let den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(den) < 1e-6 { return nil }
        let t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
        return SIMD2<Float>(x1 + t * (x2 - x1), y1 + t * (y2 - y1))
    }
}
