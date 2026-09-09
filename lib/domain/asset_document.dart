import '../core/network/envelope.dart';

/// One row from `GET /api/fm/assets/:id/documents` — a file or external link
/// attached to an asset (Warranty / O&M / Commissioning / Datasheet /
/// Certificates / Photos …), shown from both the Work Order detail screen and
/// the Maintenance Record detail screen for whichever asset the record is
/// against. Mirrors `normalizeAssetDocuments` in the server's
/// `assetController.ts`, which is the only place these fields are guaranteed
/// (the underlying `documents` column is a loosely-shaped JSONB array).
class AssetDocument {
  const AssetDocument({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    required this.category,
    this.mimeType,
    this.size,
    this.uploadedBy,
    this.uploadedAt,
  });

  /// Generated `ad-<ts>-<rand>` for an uploaded file; legacy rows fall back to
  /// their own URL. Either way, stable enough to key a list by.
  final String id;
  final String name;
  final String url;

  /// File extension, upper-cased (`PDF`, `JPG`, `DOCX`…) — `LINK` when the
  /// entry is an external URL rather than an uploaded file.
  final String type;

  /// One of the server's fixed documentation categories, normalized to
  /// `other` when absent or unrecognized.
  final String category;
  final String? mimeType;

  /// Bytes. Null for an external link — those cost nothing to store and carry
  /// no size.
  final int? size;
  final String? uploadedBy;
  final DateTime? uploadedAt;

  static const _imageTypes = {
    'JPG',
    'JPEG',
    'PNG',
    'GIF',
    'WEBP',
    'BMP',
    'HEIC',
    'HEIF',
  };

  /// Whether this should open in the full-screen photo viewer rather than the
  /// in-app browser. Checked by mime type first — set for every uploaded file
  /// — and falls back to the file extension for the legacy rows and external
  /// links that predate `mimeType` being stored.
  bool get isImage =>
      (mimeType?.startsWith('image/') ?? false) || _imageTypes.contains(type);

  static const _externalViewerTypes = {
    'PDF',
    'DOC',
    'DOCX',
    'XLS',
    'XLSX',
  };

  static const _externalViewerMimeTypes = {
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  /// Whether this file type has no chance of rendering in the app's in-app
  /// browser (a plain [WebViewWidget], with no PDF/Office renderer on
  /// Android) and should instead be handed straight to the system app via
  /// `url_launcher`. Checked by mime type first, falling back to the file
  /// extension for legacy rows and external links that predate `mimeType`
  /// being stored — mirrors [isImage]'s fallback shape.
  bool get isExternalViewerOnly =>
      (mimeType != null &&
          _externalViewerMimeTypes.contains(mimeType!.toLowerCase())) ||
      _externalViewerTypes.contains(type);

  factory AssetDocument.fromJson(Map<String, dynamic> json) => AssetDocument(
    id: firstNonEmpty([json['id'], json['url']]) ?? '',
    name: firstNonEmpty([json['name']]) ?? 'Document',
    url: json['url']?.toString() ?? '',
    type: firstNonEmpty([json['type']])?.toUpperCase() ?? 'LINK',
    category: firstNonEmpty([json['category']])?.toLowerCase() ?? 'other',
    mimeType: json['mimeType']?.toString(),
    size: asInt(json['size']),
    uploadedBy: json['uploadedBy']?.toString(),
    uploadedAt: asDate(json['uploadedAt']),
  );

  static List<AssetDocument> listFrom(List<Map<String, dynamic>> rows) =>
      rows.map(AssetDocument.fromJson).toList();
}
