import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/asset_documents_repository.dart';
import '../domain/asset_document.dart';
import 'providers.dart';

class AssetDocumentsState {
  const AssetDocumentsState({required this.documents, required this.fromCache});

  final List<AssetDocument> documents;
  final bool fromCache;
}

/// The document list for one asset, family-keyed by asset id rather than by
/// [OrderKey] — a Work Order tab and a Maintenance Record tab that happen to
/// point at the same asset share one cached fetch instead of two, and the id
/// is all the endpoint needs.
class AssetDocumentsController
    extends FamilyAsyncNotifier<AssetDocumentsState, String> {
  @override
  Future<AssetDocumentsState> build(String assetId) async {
    final page = await ref.read(assetDocumentsRepositoryProvider).list(assetId);
    return AssetDocumentsState(
      documents: page.documents,
      fromCache: page.fromCache,
    );
  }
}

final assetDocumentsRepositoryProvider = Provider<AssetDocumentsRepository>(
  (ref) => AssetDocumentsRepository(ref.watch(syncClientProvider)),
);

final assetDocumentsControllerProvider = AsyncNotifierProvider.family<
    AssetDocumentsController, AssetDocumentsState, String>(
  AssetDocumentsController.new,
);
