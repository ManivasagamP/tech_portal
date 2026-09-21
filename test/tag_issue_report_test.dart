import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/offline/offline_db.dart';

void main() {
  group('FR-1.7 tag issue report row round-trip', () {
    test('every field survives toRow/fromRow, including the reason enum', () {
      final reportedAt = DateTime(2026, 9, 21, 14, 30);
      final report = TagIssueReport(
        assetId: 'asset-1',
        assetReferenceId: 'AST228',
        assetName: 'FR-1.1 Test Chiller',
        reason: TagIssueReason.unreadable,
        note: 'Painted over, barcode unreadable',
        reportedAt: reportedAt,
      );

      final restored = TagIssueReport.fromRow({...report.toRow(), 'id': 7});

      expect(restored.id, 7);
      expect(restored.assetId, 'asset-1');
      expect(restored.assetReferenceId, 'AST228');
      expect(restored.assetName, 'FR-1.1 Test Chiller');
      expect(restored.reason, TagIssueReason.unreadable);
      expect(restored.note, 'Painted over, barcode unreadable');
      expect(restored.reportedAt, reportedAt);
    });

    test('a null note and null reference id survive round-trip as null', () {
      final report = TagIssueReport(
        assetId: 'asset-2',
        reason: TagIssueReason.missing,
        reportedAt: DateTime(2026, 1, 1),
      );

      final restored = TagIssueReport.fromRow({...report.toRow(), 'id': 1});

      expect(restored.assetReferenceId, isNull);
      expect(restored.assetName, isNull);
      expect(restored.note, isNull);
      expect(restored.reason, TagIssueReason.missing);
    });
  });
}
