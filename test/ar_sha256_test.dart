import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/ar/sha256.dart';

void main() {
  // FIPS 180-4 / NIST test vectors (cross-checked against Python's hashlib).
  test('empty input', () {
    expect(Sha256.hex(const []), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('"abc"', () {
    expect(Sha256.hex(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('448-bit message (two blocks after padding)', () {
    expect(
      Sha256.hex(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  test('padding boundaries: 55, 64 and 1000 bytes', () {
    expect(Sha256.hex(List.filled(55, 0x61)), '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318');
    expect(Sha256.hex(List.filled(64, 0x61)), 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb');
    expect(Sha256.hex(List.filled(1000, 0x61)), '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3');
  });

  test('all byte values', () {
    final bytes = [for (var r = 0; r < 4; r++) ...List.generate(256, (i) => i)];
    expect(Sha256.hex(bytes), '785b0751fc2c53dc14a4ce3d800e69ef9ce1009eb327ccf458afe09c242c26c9');
  });
}
