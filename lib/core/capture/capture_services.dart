import 'dart:io';
import 'dart:typed_data';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

/// A photo held in memory until it is uploaded — either straight away, or by
/// the offline queue on the next flush.
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class CapturedLocation {
  const CapturedLocation({
    required this.latitude,
    required this.longitude,
    this.city,
    this.district,
  });

  final double latitude;
  final double longitude;

  /// Place names for the coordinates, when the device could resolve them.
  /// Always optional: the coordinates are the record, these two are the
  /// readable label put beside them.
  final String? city;
  final String? district;

  /// "Tiruppur, Tamil Nadu" — or null when neither name resolved, so callers
  /// can fall back to printing the numbers.
  String? get placeLabel {
    final parts = [city, district].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// Thrown when the technician can be told what to do about it.
class CaptureFailure implements Exception {
  const CaptureFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class PhotoCapture {
  PhotoCapture([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Verification selfie. The web runs a live webcam preview; the system
  /// camera is the equivalent that works across Android and iOS without
  /// shipping a preview surface of our own.
  Future<CapturedPhoto?> takeFacePhoto() => _take(
    source: ImageSource.camera,
    camera: CameraDevice.front,
    fallbackName: 'face-capture.jpg',
  );

  Future<CapturedPhoto?> takeJobPhoto() => _take(
    source: ImageSource.camera,
    camera: CameraDevice.rear,
    fallbackName: 'photo.jpg',
  );

  Future<CapturedPhoto?> pickFromGallery() =>
      _take(source: ImageSource.gallery, fallbackName: 'attachment.jpg');

  Future<CapturedPhoto?> _take({
    required ImageSource source,
    required String fallbackName,
    CameraDevice camera = CameraDevice.rear,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      preferredCameraDevice: camera,
      // Field photos go straight into object storage and are only ever viewed
      // on a phone; full-resolution originals waste the technician's data.
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    return CapturedPhoto(
      bytes: await file.readAsBytes(),
      fileName: file.name.isEmpty ? fallbackName : file.name,
    );
  }
}

class LocationCapture {
  final _geocoding = Geocoding();

  /// Coordinates, plus the place names for them when the device can supply
  /// them.
  ///
  /// The web resolves names from the browser's *IP address* through
  /// ipgeolocation.io, which reports where the internet connection appears to
  /// be — on mobile data that is the carrier's gateway, often a different
  /// city. Here the names are reverse-geocoded from the GPS fix we already
  /// hold, by the operating system's own geocoder (Android's `Geocoder`,
  /// iOS's `CLGeocoder`). No API key to ship, nothing billed per lookup, and
  /// the answer describes where the technician actually stands.
  Future<CapturedLocation> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CaptureFailure(
        'Turn on location services to record where this task was worked.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const CaptureFailure('Please enable location access to proceed.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return _named(position.latitude, position.longitude);
  }

  /// Attaches place names to a fix, and never fails because of them: a device
  /// with no geocoder backend, no network, or an unnamed spot in the middle of
  /// a field still returns its coordinates. Losing the label must never cost
  /// us the location that gates the job.
  Future<CapturedLocation> _named(double lat, double lng) async {
    try {
      final places = await _geocoding
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 5));
      if (places.isEmpty)
        return CapturedLocation(latitude: lat, longitude: lng);

      final place = places.first;
      final city = _firstNamed([
        place.locality,
        place.subLocality,
        place.subAdministrativeArea,
      ]);
      // The district proper, falling back to the state — and never the same
      // word twice, which is common where a city names its own district.
      final district = _firstNamed([
        if (place.subAdministrativeArea != city) place.subAdministrativeArea,
        place.administrativeArea,
      ]);

      return CapturedLocation(
        latitude: lat,
        longitude: lng,
        city: city,
        district: district,
      );
    } catch (_) {
      return CapturedLocation(latitude: lat, longitude: lng);
    }
  }

  static String? _firstNamed(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}

class VoiceRecording {
  const VoiceRecording({
    required this.bytes,
    required this.fileName,
    required this.duration,
  });

  final Uint8List bytes;
  final String fileName;
  final Duration duration;
}

class VoiceCapture {
  VoiceCapture([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  /// The web caps a recording at three minutes; the same cap keeps a stray
  /// running recorder from producing an unsendable file.
  static const maxDuration = Duration(minutes: 3);

  final AudioRecorder _recorder;
  String? _path;
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  /// Live mic level while recording, for a waveform display. Only emits
  /// between [start] and [stop]/[cancel] — the underlying recorder has
  /// nothing to report outside that window.
  Stream<Amplitude> amplitudeStream({
    Duration interval = const Duration(milliseconds: 100),
  }) => _recorder.onAmplitudeChanged(interval);

  Future<void> start(String directory) async {
    if (!await _recorder.hasPermission()) {
      throw const CaptureFailure(
        'Microphone access is needed to record a voice note.',
      );
    }
    final path = '$directory/note-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _path = path;
    _startedAt = DateTime.now();
  }

  /// Returns null when the recorder produced nothing to send.
  Future<VoiceRecording?> stop() async {
    final startedAt = _startedAt;
    _startedAt = null;
    await _recorder.stop();

    final path = _path;
    _path = null;
    if (path == null || startedAt == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    if (bytes.isEmpty) return null;

    return VoiceRecording(
      bytes: bytes,
      fileName: path.split(Platform.pathSeparator).last,
      duration: DateTime.now().difference(startedAt),
    );
  }

  Future<void> cancel() async {
    _startedAt = null;
    await _recorder.cancel();
    final path = _path;
    _path = null;
    if (path == null) return;
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  Future<void> dispose() => _recorder.dispose();
}
