import 'dart:convert';

import '../../app/env.dart';

/// What a scanned code resolved to for the c2o field-verification flow —
/// separate from the general Asset/WorkOrder/Material scheme in
/// `core/utils/qr_payload.dart`.
///
/// Mirrors the server's `buildScanPayload()` (fieldVerificationService.ts).
/// The printed c2o tag carries
///   `{"type":"C2oAsset","id":"<assetId>","t":"<16-hex token>"}`
/// and the "open in browser" link on the same tag sheet carries the same
/// pair as a URL: `{webBaseUrl}/public/c2o-verify/{id}?t={token}`.
///
/// A plain `{"type":"Asset","id":"<assetReferenceId or uuid>"}` — the
/// general FM asset label printed outside c2o (`AssetLabel.tsx`) — also
/// resolves here, without a token: those assets are trusted via the
/// technician's signed-in session and pre-downloaded pack, not a sticker
/// signature, since that label format was never designed to carry one.
///
/// A bare string with no JSON and no URL scheme (FR-1.3 — what a Code
/// 128/39 asset plate actually contains) is treated the same tokenless way.
class C2oScanTarget {
  const C2oScanTarget({required this.assetId, this.token});

  /// Either the real asset id or, for the tokenless general label, whatever
  /// `assetReferenceId || id` was baked into that sticker — the caller must
  /// match on both when looking this up locally.
  final String assetId;

  /// Null only for the tokenless general Asset label.
  final String? token;
}

C2oScanTarget? parseC2oScanTarget(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('{')) {
    return _fromJson(trimmed);
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    final web = Uri.tryParse(Env.webBaseUrl);
    final sameOrigin = web != null &&
        uri.scheme == web.scheme &&
        uri.host == web.host &&
        uri.port == web.port;
    if (!sameOrigin) return null; // A foreign link — not ours to resolve.

    final match = RegExp(r'^/public/c2o-verify/([^/]+)$').firstMatch(uri.path);
    final id = match?.group(1);
    if (id == null || id.isEmpty) return null;

    final token = uri.queryParameters['t'];
    return C2oScanTarget(
      assetId: id,
      token: token != null && token.isNotEmpty ? token : null,
    );
  }

  return _bareIdentifier(trimmed);
}

/// FR-1.3 — a Code 128/39 asset plate carries no JSON, no URL, just the bare
/// reference id or serial printed on it. Resolved the same tokenless way as
/// the general Asset label: local-cache lookup only, matched against
/// [CachedC2oAsset.assetReferenceId] as well as the real id. An uncached or
/// unrelated bare string (product barcodes, stray text) costs nothing — the
/// resolver's tokenless-and-uncached path defers rather than guessing, so
/// this always falls through cleanly to the general scanner.
C2oScanTarget? _bareIdentifier(String trimmed) {
  if (trimmed.length > 64 || trimmed.contains('\n')) return null;
  return C2oScanTarget(assetId: trimmed);
}

C2oScanTarget? _fromJson(String trimmed) {
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;

    final id = decoded['id'];
    if (id is! String || id.isEmpty) return null;

    switch (decoded['type']) {
      case 'C2oAsset':
        final token = decoded['t'];
        return C2oScanTarget(
          assetId: id,
          token: token is String && token.isNotEmpty ? token : null,
        );
      case 'Asset':
        return C2oScanTarget(assetId: id);
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}
