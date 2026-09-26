import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/marker_code.dart';

void main() {
  group('MarkerCode — CONTRACT C1 goldens (shared with the server)', () {
    const goldens = {
      '7K3QX9': '7K3QX9R',
      '4Q2MA7': '4Q2MA76',
      '000000': '0000000',
      'ZZZZZZ': 'ZZZZZZW',
      'M0R5E8': 'M0R5E85',
    };

    goldens.forEach((body, full) {
      test('$body → $full', () {
        expect(body + MarkerCode.checkChar(body), full);
        expect(MarkerCode.isValid(full), isTrue);
      });
    });

    test('the mockups\' 7K3QX9-M is sample text, not a valid code', () {
      expect(MarkerCode.normalize('7K3QX9-M'), isNull);
    });

    test('checkChar rejects a body that is not 6 alphabet characters', () {
      expect(() => MarkerCode.checkChar('7K3QX'), throwsArgumentError);
      expect(() => MarkerCode.checkChar('7K3QXU'), throwsArgumentError);
    });

    test('every single-character substitution is caught by the check', () {
      const body = '7K3QX9';
      final check = MarkerCode.checkChar(body);
      for (var i = 0; i < 6; i++) {
        for (final c in MarkerCode.alphabet.split('')) {
          if (c == body[i]) continue;
          final wrong = body.replaceRange(i, i + 1, c);
          expect(MarkerCode.checkChar(wrong), isNot(check), reason: wrong);
        }
      }
    });
  });

  group('MarkerCode.normalize', () {
    test('accepts case, hyphen and spaces', () {
      expect(MarkerCode.normalize('7k3qx9-r'), '7K3QX9R');
      expect(MarkerCode.normalize(' 7K3 QX9 R '), '7K3QX9R');
      expect(MarkerCode.normalize('7K3QX9R'), '7K3QX9R');
    });

    test('maps O → 0 and I/L → 1 (Crockford look-alikes)', () {
      expect(MarkerCode.normalize('OOOOOO-O'), '0000000');
      // 1K3QX9 → check computed from the canonical body.
      final canonical = '1K3QX9${MarkerCode.checkChar('1K3QX9')}';
      expect(MarkerCode.normalize('IK3QX9${canonical[6]}'), canonical);
      expect(MarkerCode.normalize('lK3QX9${canonical[6]}'), canonical);
    });

    test('rejects U, wrong length and a bad check', () {
      expect(MarkerCode.normalize('7K3QU9R'), isNull);
      expect(MarkerCode.normalize('7K3QX9'), isNull);
      expect(MarkerCode.normalize('7K3QX9RR'), isNull);
      expect(MarkerCode.normalize('7K3QX9S'), isNull);
      expect(MarkerCode.normalize(''), isNull);
    });

    test('isValid is strict about the canonical form', () {
      expect(MarkerCode.isValid('7K3QX9R'), isTrue);
      expect(MarkerCode.isValid('7K3QX9-R'), isFalse);
      expect(MarkerCode.isValid('7k3qx9r'), isFalse);
    });
  });

  group('MarkerCode.display / spareLabel / qrPayload', () {
    test('display inserts the hyphen before the check', () {
      expect(MarkerCode.display('7K3QX9R'), '7K3QX9-R');
      expect(MarkerCode.display('7k3qx9-r'), '7K3QX9-R');
    });

    test('display leaves an invalid value readable instead of throwing', () {
      expect(MarkerCode.display('abc'), 'ABC');
    });

    test('spare label is SP- plus the first four characters', () {
      expect(MarkerCode.spareLabel('4Q2MA76'), 'SP-4Q2M');
    });

    test('QR payload is upper case (alphanumeric mode) and ≤ 38 chars for a 10-char host', () {
      final payload = MarkerCode.qrPayload('7K3QX9R', webHost: 'fe.example');
      expect(payload, 'HTTPS://FE.EXAMPLE/M/7K3QX9-R');
      expect(payload, payload.toUpperCase());
      expect(payload.length, lessThanOrEqualTo(38));
    });
  });

  group('MarkerCode.fromScan — runs before the C2O and general schemes', () {
    test('the printed upper-case URL', () {
      expect(MarkerCode.fromScan('HTTPS://FE.EXAMPLE/M/7K3QX9-R'), '7K3QX9R');
    });

    test('any case, http or https, any host, trailing slash, query or fragment', () {
      expect(MarkerCode.fromScan('https://dev.eco.thefusionapps.com/m/7k3qx9-r'), '7K3QX9R');
      expect(MarkerCode.fromScan('http://192.168.0.142:3000/M/7K3QX9R/'), '7K3QX9R');
      expect(MarkerCode.fromScan('https://x.io/m/7K3QX9-R?src=print'), '7K3QX9R');
      expect(MarkerCode.fromScan('https://x.io/M/7K3QX9-R#top'), '7K3QX9R');
    });

    test('a bare code', () {
      expect(MarkerCode.fromScan('7K3QX9-R'), '7K3QX9R');
      expect(MarkerCode.fromScan(' 7k3qx9r '), '7K3QX9R');
    });

    test('a bare code is refused when allowBare is false', () {
      expect(MarkerCode.fromScan('7K3QX9R', allowBare: false), isNull);
      expect(MarkerCode.fromScan('HTTPS://FE.EXAMPLE/M/7K3QX9-R', allowBare: false), '7K3QX9R');
    });

    test('a board URL with a bad check is "not a marker", so it falls through', () {
      expect(MarkerCode.fromScan('HTTPS://FE.EXAMPLE/M/7K3QX9-M'), isNull);
    });

    test('other links and payloads are not markers', () {
      expect(MarkerCode.fromScan('https://x.io/public/c2o-verify/abc?t=0123456789abcdef'), isNull);
      expect(MarkerCode.fromScan('https://x.io/m/7K3QX9-R/extra'), isNull);
      expect(MarkerCode.fromScan('{"type":"Asset","id":"AST-001"}'), isNull);
      expect(MarkerCode.fromScan(''), isNull);
      expect(MarkerCode.fromScan('ftp://x.io/m/7K3QX9-R'), isNull);
    });
  });
}
