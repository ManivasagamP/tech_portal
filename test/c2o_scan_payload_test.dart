import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/app/env.dart';
import 'package:technician_portal/core/c2o/c2o_scan_payload.dart';

void main() {
  group('c2o scan targets', () {
    test('a c2o tag carries the asset id and its token', () {
      final target =
          parseC2oScanTarget('{"type":"C2oAsset","id":"asset-1","t":"abc123ef01234567"}');

      expect(target, isNotNull);
      expect(target!.assetId, 'asset-1');
      expect(target.token, 'abc123ef01234567');
    });

    test('the tokenless general Asset label still resolves, without a token', () {
      final target = parseC2oScanTarget('{"type":"Asset","id":"FE-AHU-001"}');

      expect(target, isNotNull);
      expect(target!.assetId, 'FE-AHU-001');
      expect(target.token, isNull);
    });

    test('the "open in browser" link on the tag sheet parses the same way', () {
      final target = parseC2oScanTarget(
        '${Env.webBaseUrl}/public/c2o-verify/asset-1?t=abc123ef01234567',
      );

      expect(target, isNotNull);
      expect(target!.assetId, 'asset-1');
      expect(target.token, 'abc123ef01234567');
    });

    test('a link on another host is not treated as a c2o tag', () {
      expect(
        parseC2oScanTarget('https://example.com/public/c2o-verify/asset-1?t=abc'),
        isNull,
      );
    });

    test('WorkOrder and Material codes are not c2o targets', () {
      expect(parseC2oScanTarget('{"type":"WorkOrder","id":"wo-1"}'), isNull);
      expect(parseC2oScanTarget('{"type":"Material","id":"m-1"}'), isNull);
    });

    test('a malformed or empty JSON payload does not parse', () {
      for (final raw in [
        '{"type":"C2oAsset"}', // no id
        '{"type":"C2oAsset","id":""}', // empty id
        '{not json at all',
        '',
        '   ',
      ]) {
        expect(parseC2oScanTarget(raw), isNull, reason: 'should not parse: $raw');
      }
    });
  });

  group('bare identifiers (FR-1.3 — Code 128/39 asset plates)', () {
    test('a barcode value with no JSON and no URL scheme is a tokenless target', () {
      final target = parseC2oScanTarget('AST228');

      expect(target, isNotNull);
      expect(target!.assetId, 'AST228');
      expect(target.token, isNull);
    });

    test('free text also parses as a tokenless target — the resolver defers, not this', () {
      // Whether this is actually an asset is the resolver's job (cache hit
      // vs. defer to the general scanner) — parsing alone can't tell a real
      // reference id from stray text, and shouldn't try to.
      final target = parseC2oScanTarget('CHILLER-04 filter housing');

      expect(target, isNotNull);
      expect(target!.assetId, 'CHILLER-04 filter housing');
      expect(target.token, isNull);
    });

    test('a foreign link is still never treated as a bare identifier', () {
      expect(parseC2oScanTarget('https://example.com/thing'), isNull);
    });

    test('unreasonably long or multiline content is rejected', () {
      expect(parseC2oScanTarget('x' * 65), isNull);
      expect(parseC2oScanTarget('line one\nline two'), isNull);
    });
  });
}
