import 'package:geolocator/geolocator.dart';

import '../capture/capture_services.dart' show CaptureFailure;

/// A bare coordinate pair for the location check-in — no reverse geocoding,
/// unlike [LocationCapture] (`core/capture/capture_services.dart`), which
/// this deliberately does not reuse: the check-in only needs lat/lng for
/// `POST /api/fm/technicians/me/location`, not a place label.
class CheckInPosition {
  const CheckInPosition({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

/// Same permission/service/timeout/fallback sequence as
/// `LocationCapture.current()` — kept in step deliberately so the two GPS
/// entry points in the app behave identically to the technician.
Future<CheckInPosition> currentCheckInPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const CaptureFailure(
      'Turn on location services to check in.',
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const CaptureFailure('Please enable location access to check in.');
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return CheckInPosition(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      return CheckInPosition(latitude: last.latitude, longitude: last.longitude);
    }
    throw const CaptureFailure('Could not get your location.');
  }
}
