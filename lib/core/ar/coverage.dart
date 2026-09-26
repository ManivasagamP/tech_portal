import 'dart:math' as math;

/// Predicted overlay accuracy per floor cell (CONTRACT C3,
/// docs/ar-markers-and-qr.md §4.1). A port of the server's
/// `src/services/ar/coverage.ts`, which the web heatmap and the server's
/// placement suggestions also use; all three assert the same golden cells
/// (test/ar_coverage_test.dart). The app uses it to choose where a ghost
/// board would help most ("leave a board", `ghost_spot.dart`).
///
/// v1 ignores walls: a marker is "visible" from any cell within 12 m.
class CoverageMarker {
  const CoverageMarker({
    required this.x,
    required this.z,
    required this.accuracyClass,
  });

  final double x;
  final double z;

  /// `surveyed | feature | derived`.
  final String accuracyClass;
}

enum CoverageBucket { good, ok, poor }

abstract final class ArCoverage {
  static const visibleWithinM = 12.0;
  static const cellSizeM = 0.5;
  static const goodM = 0.03;
  static const okM = 0.10;

  /// One degree in radians, rounded as the contract fixes it (0.01745), so
  /// every implementation produces bit-comparable goldens.
  static const _oneDegree = 0.01745;

  /// Spread (RMS distance from the markers' centroid) under which positions
  /// can't fix the heading, so the single-marker formula applies.
  static const _minSpreadM = 0.75;

  static double sigmaOf(String accuracyClass) => switch (accuracyClass) {
        'surveyed' => 0.005,
        'feature' => 0.02,
        _ => 0.03,
      };

  /// Predicted error in metres at cell (x, z), or null when no marker is
  /// within [visibleWithinM].
  ///
  /// - One visible marker (or a cluster under 0.75 m RMS): the best marker's
  ///   σ plus a 1° heading error swung over the distance from the cluster.
  /// - Otherwise: position error `σp/√n` plus heading error
  ///   `σp / (r_rms·√n)` swung over the distance from the centroid.
  static double? cellError(List<CoverageMarker> markers, double x, double z) {
    final visible = <CoverageMarker>[
      for (final m in markers)
        if (_dist(m.x, m.z, x, z) <= visibleWithinM) m,
    ];
    final n = visible.length;
    if (n == 0) return null;

    var sigma2Sum = 0.0;
    var minSigma = double.infinity;
    var cx = 0.0;
    var cz = 0.0;
    for (final m in visible) {
      final s = sigmaOf(m.accuracyClass);
      sigma2Sum += s * s;
      minSigma = math.min(minSigma, s);
      cx += m.x;
      cz += m.z;
    }
    cx /= n;
    cz /= n;
    final sigmaP = math.sqrt(sigma2Sum / n);

    var r2Sum = 0.0;
    for (final m in visible) {
      final d = _dist(m.x, m.z, cx, cz);
      r2Sum += d * d;
    }
    final rRms = math.sqrt(r2Sum / n);
    final d = _dist(x, z, cx, cz);

    if (n == 1 || rRms < _minSpreadM) {
      final swing = _oneDegree * d;
      return math.sqrt(minSigma * minSigma + swing * swing);
    }
    final sqrtN = math.sqrt(n);
    final sigmaYaw = sigmaP / (rRms * sqrtN);
    final position = sigmaP / sqrtN;
    final swing = sigmaYaw * d;
    return math.sqrt(position * position + swing * swing);
  }

  static CoverageBucket bucket(double? e) {
    if (e == null || e > okM) return CoverageBucket.poor;
    if (e <= goodM) return CoverageBucket.good;
    return CoverageBucket.ok;
  }

  /// Share (0–1) of [cells] predicted at 10 cm or better. [cells] are the
  /// 0.5 m cell centres inside the floor's spaces, as `(x, z)` records.
  static double coverageShare(
    List<CoverageMarker> markers,
    List<(double, double)> cells,
  ) {
    if (cells.isEmpty) return 0;
    var covered = 0;
    for (final (x, z) in cells) {
      final e = cellError(markers, x, z);
      if (e != null && e <= okM) covered++;
    }
    return covered / cells.length;
  }

  static double _dist(double x0, double z0, double x1, double z1) {
    final dx = x1 - x0;
    final dz = z1 - z0;
    return math.sqrt(dx * dx + dz * dz);
  }
}
