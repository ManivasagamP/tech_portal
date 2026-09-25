import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/env.dart';
import '../network/api_client.dart';
import '../storage/secure_store.dart';
import '../storage/session_store.dart';
import 'offline_db.dart';
import 'queue_bus.dart';
import 'sync_client.dart';

/// FR-4.4 — drain the offline queue when the app isn't running.
///
/// Before this, the queue only drained while the app was open (a
/// connectivity listener plus a 20s poll inside [SyncClient.startAutoFlush]).
/// A technician who resurfaced with a full queue and pocketed the phone, or
/// whose phone killed the app to save battery, uploaded nothing until they
/// happened to open the app again. The plan's promise ("the evidence reaches
/// the project team when they resurface") depended on them remembering to.
///
/// Two Android WorkManager jobs, both requiring a network connection:
/// - **soon**: a one-off job queued the moment a write lands in the queue.
///   WorkManager holds it until the phone has signal, then runs it, even if
///   the app was killed in the meantime. This is the "on connectivity
///   regain" trigger.
/// - **periodic**: every 15 minutes (Android's floor) as a backstop, for
///   anything a previous run couldn't finish (a 5xx, an expired session
///   that was since renewed).
///
/// Both run [runBackgroundSync], which rebuilds the same [SyncClient] the
/// app uses, so the replay rules are identical in both places. The flush
/// lease (`SyncLease`) keeps the app and a background run from draining at
/// the same moment.
///
/// Android only for now. iOS needs BGTaskScheduler identifiers in
/// Info.plist and registration in AppDelegate, which can't be built or
/// verified from this (Windows) toolchain; there the in-app flush remains
/// the only trigger.
class BackgroundSync {
  static const soonTask = 'fe.sync.soon';
  static const periodicTask = 'fe.sync.periodic';
  static const _taskName = 'drainOfflineQueue';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Called once from `main()`. Safe to call on every launch: the periodic
  /// job is registered with `keep`, so an existing schedule isn't reset.
  static Future<void> init() async {
    if (!_supported) return;
    try {
      await Workmanager().initialize(backgroundSyncDispatcher);
      await Workmanager().registerPeriodicTask(
        periodicTask,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (e) {
      // Background sync is a backstop. Failing to schedule it must never
      // stop the app from starting; the in-app flush still works.
      debugPrint('BackgroundSync.init failed: $e');
    }
  }

  /// Something was just queued: ask the OS to drain as soon as there's a
  /// connection. `keep`, because one pending job drains the whole queue, so
  /// ten queued checks need one job, not ten.
  static void requestSoon() {
    if (!_supported) return;
    Workmanager()
        .registerOneOffTask(
          soonTask,
          _taskName,
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingWorkPolicy.keep,
        )
        .catchError(
          (Object e) => debugPrint('BackgroundSync.requestSoon failed: $e'),
        );
  }

  // No cancel on sign-out: a run with no stored token returns immediately
  // (see [runBackgroundSync]), so a signed-out phone never uploads as anyone.
}

/// Entry point WorkManager calls in a fresh background engine. Must be
/// top-level and kept by the tree-shaker.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      await runBackgroundSync();
    } catch (e) {
      debugPrint('Background sync run failed: $e');
    }
    // Always "success": WorkManager's own retry would only repeat what the
    // periodic job does anyway, and a failed run must not pile up retries.
    return true;
  });
}

/// One background drain. Returns how many mutations were still queued
/// afterwards (null if it didn't run), for logging and tests.
Future<int?> runBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();

  final secureStore = SecureStore();
  // Signed out → there's nobody to upload as. The queue is kept; it drains
  // the next time someone signs in.
  final token = await secureStore.readToken();
  if (token == null || token.isEmpty) return null;

  // Never mint a passphrase here: a background run creating a new one would
  // make the real database unreadable. No passphrase means no database yet.
  final passphrase = await secureStore.readDbPassphrase();
  if (passphrase == null) return null;

  final db = await OfflineDb.open(passphrase: passphrase);
  if (await db.countMutations() == 0) return 0;

  final sessionStore = await SessionStore.open();
  final api = ApiClient(
    secureStore: secureStore,
    baseUrl: sessionStore.readBaseUrlOverride() ?? Env.defaultApiBaseUrl,
  );
  final bus = QueueBus();
  try {
    await SyncClient(api: api, db: db, bus: bus).flushQueue();
    final left = await db.countMutations();
    debugPrint('Background sync: $left left in queue');
    return left;
  } finally {
    // Deliberately NOT closing `db`: sqflite shares one native connection
    // per file across engines, so closing it here would pull the database
    // out from under the app if it's open at the same time.
    bus.dispose();
    api.dispose();
  }
}
