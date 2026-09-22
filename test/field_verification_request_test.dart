import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/data/field_verification_repository.dart';

void main() {
  group('FR-3 — FieldVerificationRequest.toJson', () {
    test('a bare result with nothing else observed sends only what was set', () {
      final json = const FieldVerificationRequest(result: VerificationResult.verified).toJson();
      expect(json['result'], 'verified');
      expect(json.containsKey('observedSerial'), isFalse);
      expect(json.containsKey('observedTag'), isFalse);
      expect(json.containsKey('observedCondition'), isFalse);
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('photos'), isFalse);
      expect(json.containsKey('geo'), isFalse);
    });

    test('every field maps to the server enum names exactly', () {
      final json = const FieldVerificationRequest(
        result: VerificationResult.mismatch,
        observedSerial: 'SN-123',
        observedTag: 'AST-9',
        observedCondition: ObservedCondition.poor,
        notes: 'Cracked housing',
      ).toJson();

      expect(json['result'], 'mismatch');
      expect(json['observedSerial'], 'SN-123');
      expect(json['observedTag'], 'AST-9');
      expect(json['observedCondition'], 'poor');
      expect(json['notes'], 'Cracked housing');
    });

    test('the fifth result value is "inaccessible", not "needs-follow-up"', () {
      final json = const FieldVerificationRequest(result: VerificationResult.inaccessible).toJson();
      expect(json['result'], 'inaccessible');
    });

    test('photos serialize as {dataBase64, name, contentType} entries', () {
      final json = const FieldVerificationRequest(
        result: VerificationResult.verified,
        photos: [
          VerificationPhoto(dataUrl: 'data:image/jpeg;base64,AAAA', fileName: 'a.jpg', contentType: 'image/jpeg'),
        ],
      ).toJson();

      final photos = json['photos'] as List;
      expect(photos, hasLength(1));
      expect(photos.single, {
        'dataBase64': 'data:image/jpeg;base64,AAAA',
        'name': 'a.jpg',
        'contentType': 'image/jpeg',
      });
    });

    test('lat/lng only appear together, with accuracy folded into geo', () {
      final json = const FieldVerificationRequest(
        result: VerificationResult.verified,
        latitude: 25.2,
        longitude: 55.3,
        gpsAccuracy: 12.5,
      ).toJson();

      expect(json['geo'], {'lat': 25.2, 'lng': 55.3, 'accuracy': 12.5});
    });

    test('no latitude means no geo key at all, not a half-filled one', () {
      final json = const FieldVerificationRequest(result: VerificationResult.verified).toJson();
      expect(json.containsKey('geo'), isFalse);
    });
  });
}
