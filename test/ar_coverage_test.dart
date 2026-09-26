import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/coverage.dart';

CoverageMarker _m(double x, double z, String cls) =>
    CoverageMarker(x: x, z: z, accuracyClass: cls);

void main() {
  group('CONTRACT C3 goldens (shared with the server and the web heatmap)', () {
    test('one feature board, 5 m away → 0.08951', () {
      expect(ArCoverage.cellError([_m(0, 0, 'feature')], 5, 0), closeTo(0.08951, 5e-6));
    });

    test('two feature boards 5 m apart, cell (2.5, 4) → 0.02668', () {
      expect(
        ArCoverage.cellError([_m(0, 0, 'feature'), _m(5, 0, 'feature')], 2.5, 4),
        closeTo(0.02668, 5e-6),
      );
    });

    test('four surveyed boards on an 8 m square, centre → 0.0025', () {
      final markers = [
        _m(0, 0, 'surveyed'),
        _m(8, 0, 'surveyed'),
        _m(0, 8, 'surveyed'),
        _m(8, 8, 'surveyed'),
      ];
      expect(ArCoverage.cellError(markers, 4, 4), closeTo(0.0025, 5e-7));
    });

    test('a derived board 13 m away is not visible → null', () {
      expect(ArCoverage.cellError([_m(0, 0, 'derived')], 13, 0), isNull);
    });

    test('two boards 0.5 m apart count as one cluster → 0.05199', () {
      expect(
        ArCoverage.cellError([_m(0, 0, 'feature'), _m(0.5, 0, 'feature')], 3, 0),
        closeTo(0.05199, 5e-6),
      );
    });
  });

  group('buckets and share', () {
    test('good ≤ 3 cm, ok ≤ 10 cm, poor above or unseen', () {
      expect(ArCoverage.bucket(0.03), CoverageBucket.good);
      expect(ArCoverage.bucket(0.031), CoverageBucket.ok);
      expect(ArCoverage.bucket(0.10), CoverageBucket.ok);
      expect(ArCoverage.bucket(0.1001), CoverageBucket.poor);
      expect(ArCoverage.bucket(null), CoverageBucket.poor);
    });

    test('coverage = share of cells at 10 cm or better', () {
      final markers = [_m(0, 0, 'feature')];
      // 5 m → 0.0895 (covered); 13 m → unseen; 7 m → ~0.124 (not covered).
      final share = ArCoverage.coverageShare(markers, const [(5.0, 0.0), (13.0, 0.0), (7.0, 0.0), (1.0, 0.0)]);
      expect(share, closeTo(0.5, 1e-12));
      expect(ArCoverage.coverageShare(markers, const []), 0);
    });
  });
}
