import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ar_catalog_controller.dart';
import 'ar_session_controller.dart' show arErrorKey;
import 'ar_view_models.dart';

/// Floor packs downloading in the background (models picker → "Update
/// 1.2 MB" / "Get it for offline"). Not auto-disposed: a download keeps
/// going when the technician leaves the picker, and the picker shows it
/// again when they come back. One download per floor at a time.
///
/// The session downloads its own floor too (focus tiles first, §7 rule 4);
/// both go through the same gateway, and tiles are content-addressed, so a
/// floor downloaded here is simply "already local" there.
class ArDownloadsController extends Notifier<Map<String, ArDownloadProgress>> {
  final _running = <String>{};

  @override
  Map<String, ArDownloadProgress> build() => const {};

  bool isRunning(String floorId) => _running.contains(floorId);

  Future<void> downloadFloor(String floorId) async {
    if (_running.contains(floorId)) return;
    _running.add(floorId);
    _put(floorId, const ArDownloadProgress());
    try {
      final gateway = ref.read(arGatewayProvider);
      final floor = await gateway.floorContext(floorId);
      await gateway.download(floor, onProgress: (p) => _put(floorId, p));
      _put(
        floorId,
        ArDownloadProgress(
          focusDoneBytes: floor.focusBytes,
          focusTotalBytes: floor.focusBytes,
          doneBytes: floor.totalBytes,
          totalBytes: floor.totalBytes,
          done: true,
        ),
      );
      // The picker's on-device sizes changed.
      ref.invalidate(arFloorsProvider);
    } catch (e) {
      _put(floorId, ArDownloadProgress(error: arErrorKey(e)));
    } finally {
      _running.remove(floorId);
    }
  }

  void clear(String floorId) {
    final next = {...state}..remove(floorId);
    state = next;
  }

  void _put(String floorId, ArDownloadProgress p) {
    state = {...state, floorId: p};
  }
}

final arDownloadsProvider = NotifierProvider<ArDownloadsController, Map<String, ArDownloadProgress>>(
  ArDownloadsController.new,
);
