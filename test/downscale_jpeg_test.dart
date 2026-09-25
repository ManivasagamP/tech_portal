import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:technician_portal/core/capture/capture_services.dart';

Uint8List _jpegOf(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 130, 140));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('downscaleJpeg (FR-3.4)', () {
    test('shrinks a landscape photo so its long edge is 1600px', () {
      final original = _jpegOf(4032, 3024); // a typical rear-camera photo
      final result = downscaleJpeg(original);
      final decoded = img.decodeImage(result)!;

      expect(decoded.width, 1600);
      expect(decoded.height, lessThan(3024));
      expect(result.length, lessThan(original.length));
    });

    test('shrinks a portrait photo so its long edge (height) is 1600px', () {
      final original = _jpegOf(3024, 4032);
      final result = downscaleJpeg(original);
      final decoded = img.decodeImage(result)!;

      expect(decoded.height, 1600);
      expect(decoded.width, lessThan(3024));
    });

    test('leaves an already-small photo untouched — no upscaling, no re-encode', () {
      final original = _jpegOf(800, 600);
      final result = downscaleJpeg(original);

      expect(result, same(original));
    });

    test('an image exactly at the 1600px cap is left untouched', () {
      final original = _jpegOf(1600, 1200);
      final result = downscaleJpeg(original);

      expect(result, same(original));
    });
  });
}
