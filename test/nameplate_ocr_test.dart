import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ocr/nameplate_ocr.dart';

void main() {
  group('nameplate field extraction', () {
    test('labelled fields on the same line as their value', () {
      final fields = extractNameplateFields('''
Acme Chillers Ltd
Model: XC-4000
S/N: 27673571
''');

      expect(fields.manufacturer, 'Acme Chillers Ltd');
      expect(fields.model, 'XC-4000');
      expect(fields.serial, '27673571');
    });

    test('a label sitting alone on its own line takes the next line as the value', () {
      final fields = extractNameplateFields('''
Acme Chillers Ltd
MODEL NO
XC-4000
SERIAL NUMBER
27673571
''');

      expect(fields.model, 'XC-4000');
      expect(fields.serial, '27673571');
    });

    test('with no explicit manufacturer label, the first line is the guess', () {
      final fields = extractNameplateFields('Acme Chillers Ltd\nModel: XC-4000');

      expect(fields.manufacturer, 'Acme Chillers Ltd');
    });

    test('an explicit manufacturer label overrides the first-line guess', () {
      final fields = extractNameplateFields('''
XC-4000 Series
Manufactured by: Acme Chillers Ltd
''');

      expect(fields.manufacturer, 'Acme Chillers Ltd');
    });

    test('different label spellings all resolve to the same field', () {
      expect(extractNameplateFields('Ser No: ABC1').serial, 'ABC1');
      expect(extractNameplateFields('SERIAL: ABC2').serial, 'ABC2');
      expect(extractNameplateFields('MDL: ABC3').model, 'ABC3');
      expect(extractNameplateFields('MFR: ABC4').manufacturer, 'ABC4');
    });

    test('blank OCR output leaves every field null', () {
      final fields = extractNameplateFields('');

      expect(fields.isEmpty, isTrue);
      expect(fields.manufacturer, isNull);
      expect(fields.model, isNull);
      expect(fields.serial, isNull);
    });

    test('a value is never guessed from a line that is itself another label', () {
      // "Serial Number" with nothing after it, immediately followed by
      // another label line rather than an actual value — must not borrow
      // "Model:" as the serial.
      final fields = extractNameplateFields('Serial Number\nModel: XC-4000');

      expect(fields.serial, isNull);
      expect(fields.model, 'XC-4000');
    });
  });
}
