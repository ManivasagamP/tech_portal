/// FR-5.1/SR-1 — parses the server's route-pack responses
/// (`GET /api/c2o/routes/:scope`) into typed shapes. Pure parsing, no I/O —
/// same split as `asset_detail.dart` from its repository.

/// package | building | level | system — mirrors the server's `RouteScope`.
enum RouteScope { package, building, level, system }

extension RouteScopeApi on RouteScope {
  /// The literal path segment the server expects.
  String get apiValue => name;
}

/// FR-5.1's pre-download size check — `?estimate=true`, a cheap count with
/// no per-asset payload, so the technician can see "≈340 assets, ~510 KB"
/// before committing to the real download.
class RoutePackEstimate {
  const RoutePackEstimate({required this.assetCount, required this.estimatedBytes});

  final int assetCount;
  final int estimatedBytes;

  /// NFR-4's own budget — "a full route pack of 500 assets" should stay
  /// under this on device. The estimate used to be advisory only (shown,
  /// never enforced); a technician could commit to a download this size or
  /// larger with nothing stopping them. This is the client-side ceiling
  /// until a real one comes back from the "route size ceiling" decision
  /// still open in new_plan.md.
  static const capBytes = 150 * 1024 * 1024;

  bool get exceedsCap => estimatedBytes > capBytes;

  factory RoutePackEstimate.fromJson(Map<String, dynamic> json) => RoutePackEstimate(
    assetCount: (json['assetCount'] as num?)?.toInt() ?? 0,
    estimatedBytes: (json['estimatedBytes'] as num?)?.toInt() ?? 0,
  );

  /// "512 KB" / "3.1 MB" — rough, matches what the estimate itself is.
  String get formattedSize {
    if (estimatedBytes < 1024) return '$estimatedBytes B';
    if (estimatedBytes < 1024 * 1024) {
      return '${(estimatedBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// One asset inside a downloaded route pack — the same fields
/// `AssetDetail.fromClaims` reads, plus the pack-specific extras (scan
/// token, open-finding count, last verification) a route screen needs for
/// its own list/progress view.
class RoutePackAsset {
  const RoutePackAsset({
    required this.id,
    required this.raw,
    this.assetReferenceId,
    this.assetName,
    this.scanToken,
    this.verificationStatus,
    this.openFindingCount = 0,
    this.lastVerificationResult,
  });

  final String id;
  final String? assetReferenceId;
  final String? assetName;
  final String? scanToken;

  /// "pending" | "verified" | "mismatch" | "missing" — drives FR-5.3's
  /// verified/outstanding/flagged count without a second pass over the
  /// server's shape.
  final String? verificationStatus;
  final int openFindingCount;
  final String? lastVerificationResult;

  /// The exact JSON object the server sent for this asset — carried through
  /// unparsed so it can be handed to [AssetDetail.fromClaims] (wrapped as
  /// `{'asset': raw, ...}`) without this file needing to duplicate every
  /// field `AssetDetail` already knows how to read.
  final Map<String, dynamic> raw;

  factory RoutePackAsset.fromJson(Map<String, dynamic> json) {
    final lastVerification = json['lastVerification'];
    return RoutePackAsset(
      id: json['id']?.toString() ?? '',
      assetReferenceId: json['assetReferenceId']?.toString(),
      assetName: json['assetName']?.toString(),
      scanToken: json['scanToken']?.toString(),
      verificationStatus: json['verificationStatus']?.toString(),
      openFindingCount: (json['openFindingCount'] as num?)?.toInt() ?? 0,
      lastVerificationResult:
          lastVerification is Map ? lastVerification['result']?.toString() : null,
      raw: json,
    );
  }
}

/// A full downloaded route pack (FR-5.1) with SR-2's freshness stamp.
class RoutePack {
  const RoutePack({
    required this.scope,
    required this.id,
    required this.asOf,
    required this.versionTag,
    required this.assets,
  });

  final RouteScope scope;
  final String id;

  /// When the server assembled this pack — FR-5.7's "stamp the pack, show
  /// its age" starts here.
  final DateTime asOf;

  /// SR-2's fingerprint — unchanged means a refresh can be a 304, not a
  /// re-download.
  final String versionTag;
  final List<RoutePackAsset> assets;

  int get assetCount => assets.length;

  factory RoutePack.fromJson(Map<String, dynamic> json) => RoutePack(
    scope: RouteScope.values.byName(json['scope']?.toString() ?? 'package'),
    id: json['id']?.toString() ?? '',
    asOf: DateTime.tryParse(json['asOf']?.toString() ?? '') ?? DateTime.now(),
    versionTag: json['versionTag']?.toString() ?? '',
    assets: (json['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((a) => RoutePackAsset.fromJson(Map<String, dynamic>.from(a)))
        .toList(),
  );
}
