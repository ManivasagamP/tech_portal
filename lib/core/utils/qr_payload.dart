import 'dart:convert';

import '../../app/env.dart';

/// Port of `lib/utils/qr-payload.ts`.
///
/// Stickers in the field carry a short JSON string rather than a URL:
///   `{"type":"Asset","id":"<uuid>"}`
///   `{"type":"WorkOrder","id":"<uuid>"}`
///   `{"type":"Material","id":"<uuid>"}`
///
/// Only a scanner inside the app knows how to turn that into a path, which is
/// what stops a printed code from pointing straight at a public endpoint.
enum QrEntityType {
  asset('Asset'),
  workOrder('WorkOrder'),
  material('Material');

  const QrEntityType(this.wire);

  final String wire;

  static QrEntityType? fromWire(String? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

class QrPayload {
  const QrPayload({required this.type, required this.id});

  final QrEntityType type;
  final String id;
}

/// The technician-facing destination for a payload. Assets and materials have
/// no private screen in this portal, so they fall back to the public page —
/// same as `buildTechnicianPath` on the web.
String buildTechnicianPath(QrPayload payload) => switch (payload.type) {
      QrEntityType.asset => '/public/assets/${payload.id}',
      QrEntityType.material => '/public/materials/${payload.id}',
      QrEntityType.workOrder => '/orders/work-order/${payload.id}',
    };

bool isPublicPath(String path) => path.startsWith('/public/');

/// What a scanned string turned out to be.
///
/// - [ScannedRecord] — our own JSON scheme or a same-origin `/public/*` link.
///   Either way the technician confirms before anything opens.
/// - [ScannedExternal] — anything else: a foreign link or plain text.
///   [ScannedExternal.isUrl] is true **only** for http/https.
sealed class ScanResolution {
  const ScanResolution();
}

class ScannedRecord extends ScanResolution {
  const ScannedRecord({required this.path, required this.label});

  /// Either an in-app route (`/orders/work-order/<id>`) or a `/public/*` path
  /// that opens in the built-in browser.
  final String path;

  /// What to show on the confirm button — "Work Order", "Asset", "Material".
  final String label;

  bool get isPublic => isPublicPath(path);
}

class ScannedExternal extends ScanResolution {
  const ScannedExternal({required this.value, required this.isUrl});

  final String value;
  final bool isUrl;
}

/// `Uri.parse` accepts far more than web addresses — `javascript:alert(1)`,
/// `data:text/html,<script>` and `wifi:S:...` all parse cleanly. External
/// content opens without a confirmation step, so treating every parseable URI
/// as openable would let a malicious sticker run script or render markup with
/// the technician's session. Only http and https ever launch; everything else
/// is shown as text for the person holding the phone to judge.
bool _isOpenableUrl(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

QrPayload? parseQrPayload(String raw) {
  final trimmed = raw.trim();
  // Fast rejection of plain URLs before paying for a JSON decode.
  if (!trimmed.startsWith('{')) return null;
  try {
    final decoded = _decodeJsonObject(trimmed);
    if (decoded == null) return null;
    final type = QrEntityType.fromWire(decoded['type']?.toString());
    final id = decoded['id'];
    if (type == null || id is! String || id.isEmpty) return null;
    return QrPayload(type: type, id: id);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
}

/// The single entry point every scan goes through, so the camera path and the
/// gallery path can never drift apart.
ScanResolution resolveScannedValue(String raw) {
  final payload = parseQrPayload(raw);
  if (payload != null) {
    return ScannedRecord(
      path: buildTechnicianPath(payload),
      label: switch (payload.type) {
        QrEntityType.workOrder => 'Work Order',
        QrEntityType.asset => 'Asset',
        QrEntityType.material => 'Material',
      },
    );
  }

  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme) {
    return ScannedExternal(value: raw, isUrl: false);
  }

  final web = Uri.tryParse(Env.webBaseUrl);
  final sameOrigin = web != null &&
      uri.scheme == web.scheme &&
      uri.host == web.host &&
      uri.port == web.port;

  if (sameOrigin && uri.path.startsWith('/public/') && _isOpenableUrl(uri)) {
    return ScannedRecord(path: uri.path, label: 'Record');
  }

  return ScannedExternal(value: raw, isUrl: _isOpenableUrl(uri));
}
