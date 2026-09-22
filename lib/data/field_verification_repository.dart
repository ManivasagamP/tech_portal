import '../core/offline/sync_client.dart';

/// FR-3.1 — one of five outcomes. Matches the server's enum exactly
/// (`C2oFieldVerification.result`, `fieldVerificationService.ts`); there is
/// no "needs follow-up" value on the server — [inaccessible] is that case
/// ("could not reach/verify it right now").
enum VerificationResult { verified, mismatch, missing, damaged, inaccessible }

/// FR-3.3 — matches the server's `observedCondition` enum exactly.
enum ObservedCondition { good, fair, poor, damaged }

/// A photo already captured and downscaled on-device (see
/// `PhotoCapture.takeJobPhoto`), reduced to just what the verify endpoint's
/// `photos[]` array wants — a data URL it strips the `data:...;base64,`
/// prefix from itself.
class VerificationPhoto {
  const VerificationPhoto({
    required this.dataUrl,
    required this.fileName,
    required this.contentType,
  });

  final String dataUrl;
  final String fileName;
  final String contentType;

  Map<String, dynamic> toJson() => {
    'dataBase64': dataUrl,
    'name': fileName,
    'contentType': contentType,
  };
}

/// Pure request-shaping, separated from the network call below so it can be
/// unit tested without a fake [SyncClient] — same split already used by
/// `FloorPlanRecord.fromJson` for the read side.
class FieldVerificationRequest {
  const FieldVerificationRequest({
    required this.result,
    this.observedSerial,
    this.observedTag,
    this.observedCondition,
    this.notes,
    this.photos = const [],
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    this.flagForReinspection = false,
    this.flagReason,
  });

  final VerificationResult result;
  final String? observedSerial;
  final String? observedTag;
  final ObservedCondition? observedCondition;
  final String? notes;

  /// FR-3.11 — the crew could not finish this check (blocked access, missing
  /// tool, etc.) and wants the asset requeued for a return visit, regardless
  /// of what [result] itself says.
  final bool flagForReinspection;
  final String? flagReason;

  /// Capped at 8 client-side (FR-3.4) — the server has no explicit limit.
  final List<VerificationPhoto> photos;

  // FR-3.9 — GPS fix. Floor comes from the scan route context instead
  // (`AssetDetail.floorId`), not from this request — the server's verify
  // endpoint has no floor field of its own to attach it to.
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;

  Map<String, dynamic> toJson() => {
    'result': result.name,
    'observedSerial': ?observedSerial,
    'observedTag': ?observedTag,
    'observedCondition': ?observedCondition?.name,
    'notes': ?notes,
    if (photos.isNotEmpty) 'photos': photos.map((p) => p.toJson()).toList(),
    if (latitude != null && longitude != null)
      'geo': {'lat': latitude, 'lng': longitude, 'accuracy': ?gpsAccuracy},
    if (flagForReinspection) 'flagForReinspection': true,
    if (flagForReinspection) 'flagReason': ?flagReason,
  };
}

/// Submits FR-3's capture form. Goes through [SyncClient] rather than the
/// raw API client so a verification recorded with no signal (a plant room,
/// a basement) queues like any other mutation and replays once the
/// technician is back online, instead of being lost.
class FieldVerificationRepository {
  FieldVerificationRepository(this._sync);

  final SyncClient _sync;

  Future<SyncedWrite> submit(String assetId, FieldVerificationRequest request) =>
      _sync.syncRequest(
        'post',
        '/api/c2o/assets/$assetId/verify',
        data: request.toJson(),
        label: 'Submit asset verification',
        entityType: 'Asset',
        entityId: assetId,
      );
}
