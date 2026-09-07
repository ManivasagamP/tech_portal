import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/network/envelope.dart';

void main() {
  group('unwrap', () {
    test('peels {success,data}', () {
      expect(unwrap({'success': true, 'data': 42}), 42);
    });

    test('peels {message,data}', () {
      expect(unwrap({'message': 'ok', 'data': 'x'}), 'x');
    });

    test('passes a raw record through — preventive detail has no envelope', () {
      final record = {'id': 'abc', 'pmScheduleId': 'PM0001'};
      expect(unwrap(record), record);
    });

    test('unwrapList tolerates a non-list payload', () {
      expect(unwrapList({'success': true, 'data': 'nope'}), isEmpty);
    });
  });

  group('scalar coercion', () {
    test('asDouble reads Sequelize DECIMAL strings', () {
      expect(asDouble('12.50'), 12.5);
      expect(asDouble(3), 3.0);
      expect(asDouble(null), isNull);
      expect(asDouble('not a number'), isNull);
    });

    test('asBool reads booleans, numbers and strings', () {
      expect(asBool(true), isTrue);
      expect(asBool(0), isFalse);
      expect(asBool('false'), isFalse);
      expect(asBool('maybe'), isNull);
    });

    test('asDate parses ISO UTC into local time', () {
      final parsed = asDate('2026-09-03T09:30:00.000Z');
      expect(parsed, isNotNull);
      expect(parsed!.toUtc().hour, 9);
      expect(parsed.isUtc, isFalse);
    });
  });

  group('firstNonEmpty', () {
    test('mirrors the web title fallback chain', () {
      expect(
        firstNonEmpty([null, '', '  ', 'Chiller service', 'ignored']),
        'Chiller service',
      );
    });

    test('returns null when every candidate is blank', () {
      expect(firstNonEmpty([null, '', '   ']), isNull);
    });
  });
}
