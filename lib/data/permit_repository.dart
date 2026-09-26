import 'dart:convert';

import '../core/capture/capture_services.dart';
import '../core/network/envelope.dart';
import '../core/offline/sync_client.dart';
import '../domain/permit.dart';

/// Permit to Work data access (docs/permit-to-work.md).
///
/// **No local write-ahead state, unlike Snag Assistant.** `SnagRepository`
/// keeps a full local copy in SQLCipher and applies `SnagRules` optimistically
/// offline, because a snag's rules are simple enough to port safely. A
/// permit's rules are not: `readiness` folds together approvals, gas,
/// isolations, crew, checks, conflicts and validity, and the whole point of
/// this module is that the **server** computes that fold, never the device
/// (see `domain/permit.dart`'s doc comment). Reimplementing it here would be
/// exactly the trap the spec warns against — a client-side readiness that
/// quietly drifts from the server's. So this repository does the two
/// contracts the rest of the app already trusts and nothing more:
///
/// - **Reads** go through [SyncClient.syncGet] — network with a write-through
///   cache, falling back to a non-expired cache entry offline. A technician
///   who opened a permit before losing signal can still see it (and its last
///   known `readiness`) underground.
/// - **Writes** go through [SyncClient.syncRequest] with
///   `queueOnServerError: true`, so a stop-work or gas test taken with no
///   signal is queued and replays automatically — the technician sees
///   [kOfflineQueuedMessage] and the detail screen simply does not update
///   its `readiness` until the write actually reaches the server and a
///   refresh pulls the new copy back in. That is a real UX gap (the screen
///   looks unchanged for a queued action until it syncs) accepted on purpose
///   rather than inventing a local readiness engine; see
///   docs/permit-to-work.md and PENDING P-011.
///
/// **Signature and isolation photo travel inline, not as `QueuedAttachment`s.**
/// Every other binary upload in this app (`SnagRepository`, `addSignatureItem`
/// in `checklist_repository.dart`) rides `QueuedAttachment`: the bytes go to
/// `POST /api/upload/image` and a `__pending_*__` placeholder in the JSON
/// body is swapped for the returned **URL**. The PTW contract does not take a
/// URL here — `POST /crew/:crewId/sign-on` wants
/// `{briefingAck, signature: "data:image/png;base64,…"}` and
/// `POST /isolations/:isoId/isolate` wants `{..., photo: "data:image/…;base64,…"}`
/// literally inline. Routing either through the upload endpoint would send
/// the isolate/sign-on call a value the server does not accept. So both go
/// straight into the mutation body as a data URL and ride the *ordinary*
/// queued-write path (a plain JSON `pending_mutations` row, no attachment) —
/// offline safety is unaffected, only the encoding differs. A signature from
/// the pad is small (tens of KB); an isolation photo is downscaled the same
/// way every other field photo is (`downscaleJpeg`, 1600px/quality 80 — see
/// `PhotoCapture.takeJobPhoto`), which is not a guarantee it stays under any
/// particular size, so a very detailed lock photo could still make a queued
/// mutation row larger than the rest of this app's rows. Documented as a
/// deviation rather than silently accepted; see docs/permit-to-work.md §5.
class PermitRepository {
  PermitRepository({required SyncClient sync}) : _sync = sync;

  final SyncClient _sync;

  static const entityType = 'Permit';
  static const _base = '/api/fm/permits';

  /// The catalogue (type/hazard/control/PPE/role labels, gas limits) changes
  /// only when someone edits the PTW configuration in the office — safe to
  /// hold much longer than the default 24h cache.
  static const _catalogTtl = Duration(days: 7);

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Future<PermitCatalog> catalog() async {
    final read = await _sync.syncGet('$_base/catalog', ttl: _catalogTtl);
    return PermitCatalog.fromJson(read.data);
  }

  /// `mine: 'crew'` — permits I'm on the crew of; `mine: 'raised'` — permits
  /// I requested. The hub merges and de-dupes both (state/permit_controller.dart).
  Future<List<PermitSummary>> mine(String mine) async {
    final read = await _sync.syncGet(_base, query: {'mine': mine, 'limit': 200});
    final body = unwrapMap(read.data);
    return PermitSummary.listFromJson(body['items']);
  }

  Future<PermitDetail?> detail(String id) async {
    final read = await _sync.syncGet('$_base/$id');
    return PermitDetail.fromJsonOrNull(read.data);
  }

  /// Signed-in scan of the worksite QR (same token the public check page
  /// uses) → the full permit, with `readiness` so the detail screen can
  /// offer the right action immediately.
  Future<PermitDetail?> byToken(String token) async {
    final read = await _sync.syncGet('$_base/by-token/${Uri.encodeComponent(token)}');
    return PermitDetail.fromJsonOrNull(read.data);
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// Every mutating call funnels through here: same queue-on-server-error
  /// write, same "cache the fresh copy back in on success" step, same
  /// "nothing local to roll forward to when it only queued" shape.
  Future<PermitWriteResult> _write(
    String permitId,
    String url,
    Map<String, dynamic> body,
    String label,
  ) async {
    final write = await _sync.syncRequest(
      'post',
      url,
      data: body,
      label: label,
      entityType: entityType,
      entityId: permitId,
      queueOnServerError: true,
    );
    if (!write.synced) return const PermitWriteResult(permit: null, synced: false);
    await _cacheDetail(permitId, write.data);
    return PermitWriteResult(permit: PermitDetail.fromJsonOrNull(write.data), synced: true);
  }

  /// Writes the server's fresh copy straight into the same cache slot
  /// [detail] reads from, keyed exactly as [SyncClient.syncGet] would key
  /// the `GET /:id` call — so a technician who acts while online and then
  /// loses signal a minute later still sees the post-action state offline.
  Future<void> _cacheDetail(String permitId, dynamic body) async {
    final key = _sync.cacheKey('$_base/$permitId', null);
    await _sync.db.writeCache(key, body, const Duration(days: 30));
  }

  Future<PermitWriteResult> signOn(
    String permitId,
    String crewId, {
    required bool briefingAck,
    required List<int> signaturePngBytes,
  }) => _write(
    permitId,
    '$_base/$permitId/crew/$crewId/sign-on',
    {'briefingAck': briefingAck, 'signature': _pngDataUrl(signaturePngBytes)},
    'Sign on to permit',
  );

  Future<PermitWriteResult> signOff(String permitId, String crewId) =>
      _write(permitId, '$_base/$permitId/crew/$crewId/sign-off', const {}, 'Sign off permit');

  Future<PermitGasTestOutcome> addGasTest(
    String permitId, {
    double? o2,
    double? lel,
    double? h2s,
    double? co,
    String? instrumentId,
    DateTime? calibrationDue,
    String? location,
    String? note,
    DateTime? testedAt,
  }) async {
    final body = {
      'o2': ?o2,
      'lel': ?lel,
      'h2s': ?h2s,
      'co': ?co,
      'instrumentId': ?instrumentId,
      'calibrationDue': ?calibrationDue?.toUtc().toIso8601String(),
      'location': ?location,
      'note': ?note,
      'testedAt': (testedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    final write = await _sync.syncRequest(
      'post',
      '$_base/$permitId/gas-tests',
      data: body,
      label: 'Record gas test',
      entityType: entityType,
      entityId: permitId,
      queueOnServerError: true,
    );
    if (!write.synced) return const PermitGasTestOutcome(synced: false);
    final data = unwrapMap(write.data);
    final permitJson = data['permit'];
    if (permitJson is Map) {
      await _cacheDetail(permitId, {'success': true, 'data': permitJson});
    }
    return PermitGasTestOutcome(
      synced: true,
      permit: permitJson is Map ? PermitDetail.fromJson(Map<String, dynamic>.from(permitJson)) : null,
      test: data['test'] is Map ? PermitGasTest.fromJson(Map<String, dynamic>.from(data['test'] as Map)) : null,
      autoSuspended: asBool(data['autoSuspended']) ?? false,
    );
  }

  Future<PermitWriteResult> isolate(
    String permitId,
    String isoId, {
    String? lockNo,
    String? tagNo,
    String? note,
    CapturedPhoto? photo,
  }) => _write(
    permitId,
    '$_base/$permitId/isolations/$isoId/isolate',
    {'lockNo': ?lockNo, 'tagNo': ?tagNo, 'note': ?note, 'photo': ?photo?.dataUrl},
    'Apply isolation',
  );

  Future<PermitWriteResult> verifyIsolation(
    String permitId,
    String isoId, {
    required bool tryOut,
    String? note,
  }) => _write(
    permitId,
    '$_base/$permitId/isolations/$isoId/verify',
    {'tryOut': tryOut, 'note': ?note},
    'Verify isolation',
  );

  Future<PermitWriteResult> restoreIsolation(String permitId, String isoId) => _write(
    permitId,
    '$_base/$permitId/isolations/$isoId/restore',
    const {},
    'Restore isolation',
  );

  Future<PermitWriteResult> stopWork(String permitId, String reason) => _write(
    permitId,
    '$_base/$permitId/transition',
    {'action': 'suspend', 'reason': reason},
    'Stop work',
  );

  Future<PermitWriteResult> completeWork(String permitId, {String? comment}) => _write(
    permitId,
    '$_base/$permitId/transition',
    {'action': 'complete', 'comment': ?comment},
    'Mark work complete',
  );

  Future<PermitWriteResult> fireWatchDone(String permitId, {String? note}) => _write(
    permitId,
    '$_base/$permitId/transition',
    {'action': 'fire_watch_done', 'note': ?note},
    'Sign off fire watch',
  );

  Future<PermitWriteResult> comment(String permitId, String text) =>
      _write(permitId, '$_base/$permitId/comments', {'text': text}, 'Permit comment');

  static String _pngDataUrl(List<int> bytes) => 'data:image/png;base64,${base64Encode(bytes)}';
}

class PermitWriteResult {
  const PermitWriteResult({this.permit, required this.synced});

  /// The server's fresh copy — set only when [synced] and the endpoint
  /// returned a full `PermitDetail` (every write here except gas tests).
  final PermitDetail? permit;

  /// false = parked in the offline queue; show [kOfflineQueuedMessage] and
  /// leave the screen as is until the next successful refresh.
  final bool synced;
}

class PermitGasTestOutcome {
  const PermitGasTestOutcome({this.permit, this.test, this.autoSuspended = false, required this.synced});

  final PermitDetail? permit;
  final PermitGasTest? test;

  /// The server suspended the permit because this test failed — the sheet
  /// should say so even though the field warning ("This will stop live
  /// work") was only ever a local prediction.
  final bool autoSuspended;
  final bool synced;
}
