import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/snag.dart';

/// Snag photos and voice notes on disk, under `<documents>/snag_media/`.
///
/// Two kinds of file live here:
/// - **own captures** (`own/<snagId>/<evidenceId>.<ext>`): written the moment
///   a snag is raised, so the list, the detail screen and the duplicate
///   guard show the photo with no network — and keep showing it after sync
///   (the evidence row keeps its `localPath`).
/// - **downloaded copies** (`cache/<hash>.<ext>`): other people's photos,
///   fetched by "Download for offline" so a verifier standing in a basement
///   can still compare before and after.
///
/// The queue carries its own copy of the bytes for upload (`PendingAttachment`)
/// — deliberately separate, so clearing one can never lose the other.
class SnagMedia {
  SnagMedia({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  Directory? _root;

  Future<Directory> _dir(String sub) async {
    _root ??= Directory(p.join((await getApplicationDocumentsDirectory()).path, 'snag_media'));
    final dir = Directory(p.join(_root!.path, sub));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes an own capture and returns its absolute path.
  Future<String> saveOwn({
    required String snagId,
    required String evidenceId,
    required Uint8List bytes,
    String extension = 'jpg',
  }) async {
    final dir = await _dir(p.join('own', snagId));
    final file = File(p.join(dir.path, '$evidenceId.$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// The best local file for [e]: the own capture if it still exists, else a
  /// downloaded copy of its URL. Null means "only the network has it".
  Future<File?> localFile(SnagEvidence e) async {
    final own = e.localPath;
    if (own != null) {
      final f = File(own);
      if (f.existsSync()) return f;
    }
    final url = e.url;
    if (url == null) return null;
    final cached = await _cacheFile(url);
    return cached.existsSync() ? cached : null;
  }

  /// Downloads [url] into the cache unless it is already there. Writes to a
  /// `.part` file first so a kill mid-download never leaves a truncated file
  /// under the real name (same rule as `FloorPlanImageCache`).
  Future<File> download(String url) async {
    final file = await _cacheFile(url);
    if (file.existsSync()) return file;
    final response = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw StateError('Empty download: $url');
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return file;
  }

  /// Best-effort bulk download; returns how many files are now available
  /// offline. A single failure never stops the rest.
  Future<int> prefetch(Iterable<SnagEvidence> evidence) async {
    var ok = 0;
    for (final e in evidence) {
      if (!e.isPhoto) continue;
      if (await localFile(e) != null) {
        ok++;
        continue;
      }
      final url = e.url;
      if (url == null) continue;
      try {
        await download(url);
        ok++;
      } catch (_) {
        // Keep going: one missing photo shouldn't cost the other fifty.
      }
    }
    return ok;
  }

  Future<File> _cacheFile(String url) async {
    final dir = await _dir('cache');
    final uri = Uri.tryParse(url);
    final ext = p.extension(uri?.path ?? '').replaceAll('.', '');
    // A stable, filesystem-safe key without pulling in a hashing package.
    final key = url.codeUnits.fold<int>(0x811c9dc5, (h, c) => ((h ^ c) * 0x01000193) & 0xffffffff);
    final name = '${key.toRadixString(16)}_${url.length}.${ext.isEmpty ? 'jpg' : ext}';
    return File(p.join(dir.path, name));
  }
}
