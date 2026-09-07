import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/utils/qr_payload.dart';

void main() {
  group('scanned payloads', () {
    test('a work order code opens the order in the app', () {
      final resolution =
          resolveScannedValue('{"type":"WorkOrder","id":"wo-123"}');

      expect(resolution, isA<ScannedRecord>());
      final record = resolution as ScannedRecord;
      expect(record.path, '/orders/work-order/wo-123');
      expect(record.isPublic, isFalse);
      expect(record.label, 'Work Order');
    });

    test('assets and materials fall back to their public pages', () {
      // Neither has a private screen in this portal, so the technician gets
      // the same page a walk-up scan would show.
      expect(
        (resolveScannedValue('{"type":"Asset","id":"a-1"}') as ScannedRecord)
            .path,
        '/public/assets/a-1',
      );
      expect(
        (resolveScannedValue('{"type":"Material","id":"m-1"}') as ScannedRecord)
            .path,
        '/public/materials/m-1',
      );
    });

    test('whitespace around the payload does not defeat it', () {
      expect(
        resolveScannedValue('  {"type":"WorkOrder","id":"wo-1"}  '),
        isA<ScannedRecord>(),
      );
    });

    test('a malformed or unknown payload is not treated as ours', () {
      for (final raw in [
        '{"type":"WorkOrder"}', // no id
        '{"type":"WorkOrder","id":""}', // empty id
        '{"type":"Invoice","id":"i-1"}', // not a type we route
        '{"type":"WorkOrder","id":12}', // id is not a string
        '{not json at all', // unparseable
      ]) {
        expect(
          parseQrPayload(raw),
          isNull,
          reason: 'should not parse: $raw',
        );
      }
    });
  });

  group('scanned links', () {
    test('one of our own public pages is offered as a record', () {
      // Env.webBaseUrl defaults to the emulator host on port 3000.
      final resolution =
          resolveScannedValue('http://10.0.2.2:3000/public/assets/a-1');

      expect(resolution, isA<ScannedRecord>());
      expect((resolution as ScannedRecord).path, '/public/assets/a-1');
    });

    test('a same-host link outside /public is just an external link', () {
      final resolution =
          resolveScannedValue('http://10.0.2.2:3000/facility-management');

      expect(resolution, isA<ScannedExternal>());
      expect((resolution as ScannedExternal).isUrl, isTrue);
    });

    test('a link on another host stays external', () {
      final resolution = resolveScannedValue('https://example.com/thing');

      expect(resolution, isA<ScannedExternal>());
      expect((resolution as ScannedExternal).isUrl, isTrue);
    });

    test('only http and https are ever openable', () {
      // The whole point of the guard: external content opens without a
      // confirmation step, so a sticker carrying script must not be launchable.
      for (final raw in [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'wifi:S:PlantRoom;T:WPA;P:hunter2;;',
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
      ]) {
        final resolution = resolveScannedValue(raw);
        expect(resolution, isA<ScannedExternal>(), reason: raw);
        expect(
          (resolution as ScannedExternal).isUrl,
          isFalse,
          reason: 'must not be openable: $raw',
        );
      }
    });

    test('plain text comes back as text', () {
      final resolution = resolveScannedValue('CHILLER-04 filter housing');

      expect(resolution, isA<ScannedExternal>());
      expect((resolution as ScannedExternal).isUrl, isFalse);
      expect(resolution.value, 'CHILLER-04 filter housing');
    });
  });
}
