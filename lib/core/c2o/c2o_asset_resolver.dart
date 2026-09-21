import '../../data/c2o_field_verification_repository.dart';
import '../network/api_exception.dart';
import '../offline/offline_db.dart';
import 'c2o_scan_payload.dart';

/// FR-1.1 — resolve a scanned c2o tag offline whenever the local cache
/// already has an answer, and only fall back to the network for an asset
/// outside it. Never recomputes or ships the server's HMAC secret: the token
/// on a cached row is the exact value the server already computed, compared
/// with plain string equality.
sealed class C2oResolution {
  const C2oResolution();
}

/// Resolved — either straight from the local cache (radio untouched) or from
/// a fresh network answer that has just been written into it.
class C2oResolved extends C2oResolution {
  const C2oResolved({
    required this.assetId,
    required this.claims,
    required this.fromCache,
  });

  final String assetId;
  final Map<String, dynamic> claims;
  final bool fromCache;
}

/// The token on the tag does not match the cached or server-side value — a
/// reprinted, tampered, or foreign sticker. Never silently accepted.
class C2oTokenMismatch extends C2oResolution {
  const C2oTokenMismatch(this.assetId);
  final String assetId;
}

/// Not in the local cache and there is no signal to ask the server. Distinct
/// from "not found" — this asset may well be genuine, it just was not part
/// of today's downloaded pack.
class C2oNeedsSignal extends C2oResolution {
  const C2oNeedsSignal(this.assetId);
  final String assetId;
}

/// The server does not know this asset id at all (404).
class C2oNotFound extends C2oResolution {
  const C2oNotFound(this.assetId);
  final String assetId;
}

class C2oAssetResolver {
  C2oAssetResolver({required C2oAssetCache db, required C2oScanFetcher repo})
    : _db = db,
      _repo = repo;

  final C2oAssetCache _db;
  final C2oScanFetcher _repo;

  /// Null means either `raw` was not a c2o scan target at all, or it was the
  /// tokenless general label with nothing cached for it yet — either way the
  /// caller falls through to the general Asset/WorkOrder/Material scanner.
  Future<C2oResolution?> resolve(String raw) async {
    final target = parseC2oScanTarget(raw);
    if (target == null) return null;
    return resolveTarget(target);
  }

  Future<C2oResolution?> resolveTarget(C2oScanTarget target) async {
    final cached = await _db.getC2oAsset(target.assetId);
    if (cached != null) {
      // A tokenless general-label scan trusts the cache on id match alone —
      // that format was never designed to carry a signature to check.
      if (target.token == null || cached.scanToken == target.token) {
        return C2oResolved(
          assetId: cached.assetId,
          claims: cached.claims,
          fromCache: true,
        );
      }
      return C2oTokenMismatch(target.assetId);
    }

    // The server's verify route requires a token unconditionally — a
    // tokenless general-label asset that is not already cached has no way
    // to resolve here at all (that format was never meant to survive a
    // round trip to this endpoint). Rather than send a doomed request and
    // misread its inevitable 403 as a tampered tag, defer to the caller's
    // fallback path — the general Asset/WorkOrder/Material scanner.
    if (target.token == null) return null;

    try {
      final claims = await _repo.fetchScanTarget(target.assetId, target.token);
      final asset = claims['asset'];
      final resolvedId = asset is Map ? asset['id']?.toString() : null;
      final assetReferenceId = asset is Map ? asset['assetReferenceId']?.toString() : null;

      await _db.upsertC2oAsset(
        CachedC2oAsset(
          assetId: resolvedId ?? target.assetId,
          assetReferenceId: assetReferenceId,
          scanToken: target.token,
          claims: claims,
          cachedAt: DateTime.now(),
        ),
      );
      return C2oResolved(
        assetId: resolvedId ?? target.assetId,
        claims: claims,
        fromCache: false,
      );
    } on NetworkFailure {
      return C2oNeedsSignal(target.assetId);
    } on HttpFailure catch (e) {
      if (e.status == 403) return C2oTokenMismatch(target.assetId);
      if (e.status == 404) return C2oNotFound(target.assetId);
      rethrow;
    }
  }
}
