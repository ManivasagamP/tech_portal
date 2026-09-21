import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/c2o/c2o_asset_resolver.dart';
import 'package:technician_portal/core/network/api_exception.dart';
import 'package:technician_portal/core/offline/offline_db.dart';
import 'package:technician_portal/data/c2o_field_verification_repository.dart';

/// In-memory stand-in for [OfflineDb]'s c2o table — no sqflite involved.
class _FakeCache implements C2oAssetCache {
  final rows = <String, CachedC2oAsset>{};

  @override
  Future<CachedC2oAsset?> getC2oAsset(String idOrReference) async =>
      rows[idOrReference];

  @override
  Future<void> upsertC2oAsset(CachedC2oAsset asset) async {
    rows[asset.assetId] = asset;
    if (asset.assetReferenceId != null) rows[asset.assetReferenceId!] = asset;
  }

  @override
  Future<List<CachedC2oAsset>> listC2oAssets() async => rows.values.toSet().toList();
}

/// Stand-in for the network call — scripted per test instead of hitting Dio.
class _FakeFetcher implements C2oScanFetcher {
  _FakeFetcher(this._answer);

  final Future<Map<String, dynamic>> Function(String assetId, String? token) _answer;

  @override
  Future<Map<String, dynamic>> fetchScanTarget(String assetId, String? token) =>
      _answer(assetId, token);
}

void main() {
  group('offline-first resolve', () {
    test('a cached asset with a matching token resolves without touching the network', () async {
      final cache = _FakeCache()
        ..rows['asset-1'] = CachedC2oAsset(
          assetId: 'asset-1',
          scanToken: 'tok-1',
          claims: {
            'asset': {'id': 'asset-1', 'assetName': 'Chiller 01'},
          },
          cachedAt: DateTime.now(),
        );
      final fetcher = _FakeFetcher((_, _) async => fail('must not hit the network'));
      final resolver = C2oAssetResolver(db: cache, repo: fetcher);

      final result = await resolver.resolve('{"type":"C2oAsset","id":"asset-1","t":"tok-1"}');

      expect(result, isA<C2oResolved>());
      final resolved = result as C2oResolved;
      expect(resolved.fromCache, isTrue);
      expect(resolved.assetId, 'asset-1');
    });

    test('a cached asset with a mismatched token is flagged, not silently accepted', () async {
      final cache = _FakeCache()
        ..rows['asset-1'] = CachedC2oAsset(
          assetId: 'asset-1',
          scanToken: 'tok-1',
          claims: {'asset': {'id': 'asset-1'}},
          cachedAt: DateTime.now(),
        );
      final resolver = C2oAssetResolver(
        db: cache,
        repo: _FakeFetcher((_, _) async => fail('must not hit the network')),
      );

      final result =
          await resolver.resolve('{"type":"C2oAsset","id":"asset-1","t":"reprinted-token"}');

      expect(result, isA<C2oTokenMismatch>());
    });

    test('the tokenless general label resolves on id match alone', () async {
      final cache = _FakeCache()
        ..rows['FE-AHU-001'] = CachedC2oAsset(
          assetId: 'asset-9',
          assetReferenceId: 'FE-AHU-001',
          claims: {'asset': {'id': 'asset-9'}},
          cachedAt: DateTime.now(),
        );
      final resolver = C2oAssetResolver(
        db: cache,
        repo: _FakeFetcher((_, _) async => fail('must not hit the network')),
      );

      final result = await resolver.resolve('{"type":"Asset","id":"FE-AHU-001"}');

      expect(result, isA<C2oResolved>());
      expect((result as C2oResolved).fromCache, isTrue);
    });

    test('an asset outside the cache falls back to the network and gets cached', () async {
      final cache = _FakeCache();
      final resolver = C2oAssetResolver(
        db: cache,
        repo: _FakeFetcher((assetId, token) async {
          expect(assetId, 'asset-2');
          expect(token, 'tok-2');
          return {
            'asset': {'id': 'asset-2', 'assetReferenceId': 'FE-PMP-002'},
          };
        }),
      );

      final result = await resolver.resolve('{"type":"C2oAsset","id":"asset-2","t":"tok-2"}');

      expect(result, isA<C2oResolved>());
      expect((result as C2oResolved).fromCache, isFalse);
      // Written through, so the next scan of the same tag resolves offline.
      expect(cache.rows['asset-2'], isNotNull);
      expect(cache.rows['asset-2']!.scanToken, 'tok-2');
    });

    test('no signal and nothing cached is reported honestly, not as a failure', () async {
      final resolver = C2oAssetResolver(
        db: _FakeCache(),
        repo: _FakeFetcher((_, _) async => throw const NetworkFailure()),
      );

      final result = await resolver.resolve('{"type":"C2oAsset","id":"asset-3","t":"tok-3"}');

      expect(result, isA<C2oNeedsSignal>());
    });

    test('a 403 from the server means the token itself is wrong', () async {
      final resolver = C2oAssetResolver(
        db: _FakeCache(),
        repo: _FakeFetcher(
          (_, _) async => throw const HttpFailure(status: 403, message: 'forbidden'),
        ),
      );

      final result = await resolver.resolve('{"type":"C2oAsset","id":"asset-4","t":"bad"}');

      expect(result, isA<C2oTokenMismatch>());
    });

    test('a 404 from the server means the asset id itself is unknown', () async {
      final resolver = C2oAssetResolver(
        db: _FakeCache(),
        repo: _FakeFetcher(
          (_, _) async => throw const HttpFailure(status: 404, message: 'not found'),
        ),
      );

      final result = await resolver.resolve('{"type":"C2oAsset","id":"ghost","t":"tok"}');

      expect(result, isA<C2oNotFound>());
    });

    test('FR-1.3 — a bare Code 128/39 barcode value resolves the same tokenless way', () async {
      final cache = _FakeCache()
        ..rows['AST228'] = CachedC2oAsset(
          assetId: 'asset-1',
          assetReferenceId: 'AST228',
          claims: {'asset': {'id': 'asset-1', 'assetName': 'FR-1.1 Test Chiller'}},
          cachedAt: DateTime.now(),
        );
      final resolver = C2oAssetResolver(
        db: cache,
        repo: _FakeFetcher((_, _) async => fail('must not hit the network')),
      );

      final result = await resolver.resolve('AST228');

      expect(result, isA<C2oResolved>());
      expect((result as C2oResolved).fromCache, isTrue);
    });

    test('an uncached tokenless label defers to the general scanner rather than guessing', () async {
      // The server's verify route requires a token unconditionally, so a
      // general Asset label with nothing cached has no legitimate way to
      // resolve here — this must not turn into a network call.
      final resolver = C2oAssetResolver(
        db: _FakeCache(),
        repo: _FakeFetcher((_, _) async => fail('must not hit the network')),
      );

      expect(await resolver.resolve('{"type":"Asset","id":"FE-NEW-001"}'), isNull);
    });

    test('a code that is not a c2o target at all resolves to null', () async {
      final resolver = C2oAssetResolver(
        db: _FakeCache(),
        repo: _FakeFetcher((_, _) async => fail('must not hit the network')),
      );

      expect(await resolver.resolve('{"type":"WorkOrder","id":"wo-1"}'), isNull);
    });
  });
}
