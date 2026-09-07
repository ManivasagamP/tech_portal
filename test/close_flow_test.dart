import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/network/api_exception.dart';
import 'package:technician_portal/core/offline/sync_client.dart';
import 'package:technician_portal/data/close_repository.dart';
import 'package:technician_portal/domain/downtime.dart';
import 'package:technician_portal/domain/maintenance_record.dart';
import 'package:technician_portal/state/close_controller.dart';

/// Records the order of the three close calls and hands back whatever the test
/// asks for.
class _FakeCloseRepository implements CloseRepository {
  _FakeCloseRepository({
    this.downtimeWrite = const SyncedWrite(synced: true),
    this.completeError,
    this.completedAfterwards = false,
  });

  final SyncedWrite downtimeWrite;
  Object? completeError;

  /// What a refetch says the record's state is, used by the 5xx recovery path.
  final bool completedAfterwards;

  final calls = <String>[];
  Map<String, dynamic>? lastComplete;
  Map<String, dynamic>? lastDowntime;

  @override
  Future<List<DowntimeWindow>> downtimeHistory(String assetId) async =>
      const [];

  @override
  Future<bool> isCompleted(OrderType type, String recordId) async {
    calls.add('verify');
    return completedAfterwards;
  }

  @override
  Future<SyncedWrite> submitRca(
    OrderType type,
    String recordId, {
    String? rootCause,
    String? rcaNotes,
  }) async {
    calls.add('rca');
    return const SyncedWrite(synced: true);
  }

  @override
  Future<SyncedWrite> patchDowntime(
    OrderType type,
    String recordId, {
    required DateTime startedAt,
    required DateTime endedAt,
    required DowntimeImpact impact,
  }) async {
    calls.add('downtime');
    lastDowntime = {
      'startedAt': startedAt,
      'endedAt': endedAt,
      'impact': impact.wire,
    };
    return downtimeWrite;
  }

  @override
  Future<SyncedWrite> complete(
    OrderType type,
    String recordId, {
    double? actualHours,
    String? rootCause,
  }) async {
    calls.add('complete');
    lastComplete = {'actualHours': actualHours, 'rootCause': rootCause};
    final error = completeError;
    if (error != null) throw error;
    return const SyncedWrite(synced: true);
  }
}

CloseRequest _request({
  String? rootCause,
  String? rcaNotes,
  DateTime? start,
  DateTime? end,
  bool hasAsset = true,
  bool hasOpenWindow = false,
  bool noEnd = false,
  double? manualHours,
}) =>
    CloseRequest(
      type: OrderType.workOrder,
      recordId: 'wo-1',
      rootCause: rootCause,
      rcaNotes: rcaNotes,
      downtimeStart: start ?? DateTime(2026, 9, 4, 8),
      downtimeEnd: noEnd ? null : (end ?? DateTime(2026, 9, 4, 11)),
      impact: DowntimeImpact.fullOutage,
      hasAsset: hasAsset,
      hasOpenWindow: hasOpenWindow,
      manualHours: manualHours,
    );

void main() {
  group('root cause requirement', () {
    test('critical and high need one, whatever the casing', () {
      expect(rcaRequiredForPriority('Critical'), isTrue);
      expect(rcaRequiredForPriority('critical'), isTrue);
      expect(rcaRequiredForPriority('High'), isTrue);
      // Reactive maintenance stores its priorities lowercase.
      expect(rcaRequiredForPriority('high'), isTrue);
    });

    test('the rest do not', () {
      expect(rcaRequiredForPriority('Medium'), isFalse);
      expect(rcaRequiredForPriority('low'), isFalse);
      expect(rcaRequiredForPriority(null), isFalse);
      expect(rcaRequiredForPriority('  '), isFalse);
    });
  });

  group('downtime windows', () {
    test('an unfinished window is open', () {
      final window = DowntimeWindow.fromJson({
        'id': 'work-order:wo-1',
        'source': 'work-order',
        'sourceId': 'wo-1',
        'startedAt': '2026-09-04T06:00:00.000Z',
        'endedAt': null,
      });
      expect(window!.isOpen, isTrue);
    });

    test('a derived window is not — nobody forgot to press stop', () {
      final window = DowntimeWindow.fromJson({
        'id': 'reactive:rm-1',
        'source': 'reactive',
        'sourceId': 'rm-1',
        'startedAt': '2026-09-04T06:00:00.000Z',
        'derived': true,
      });
      expect(window!.isOpen, isFalse);
    });

    test('a row with no start time is dropped', () {
      expect(DowntimeWindow.fromJson({'id': 'x'}), isNull);
    });
  });

  group('close sequence', () {
    test('runs root cause, then downtime, then completion', () async {
      final repository = _FakeCloseRepository();
      final result = await CloseSubmitter(repository).submit(
        _request(rootCause: 'wear', rcaNotes: 'Bearing gone'),
      );

      expect(repository.calls, ['rca', 'downtime', 'complete']);
      expect(result, isA<CloseSucceeded>());
      expect((result as CloseSucceeded).queued, isFalse);
    });

    test('skips the root-cause call when nothing was entered', () async {
      final repository = _FakeCloseRepository();
      await CloseSubmitter(repository).submit(_request());

      expect(repository.calls, ['downtime', 'complete']);
    });

    test('skips downtime when no asset is linked', () async {
      final repository = _FakeCloseRepository();
      await CloseSubmitter(repository).submit(_request(hasAsset: false));

      expect(repository.calls, ['complete']);
    });

    test('carries manual hours and the root cause into the closing call',
        () async {
      final repository = _FakeCloseRepository();
      await CloseSubmitter(repository)
          .submit(_request(rootCause: 'wear', manualHours: 2.5));

      expect(repository.lastComplete, {'actualHours': 2.5, 'rootCause': 'wear'});
    });

    test('one queued call makes the whole close queued', () async {
      final repository = _FakeCloseRepository(
        downtimeWrite: const SyncedWrite(synced: false),
      );
      final result = await CloseSubmitter(repository).submit(_request());

      expect((result as CloseSucceeded).queued, isTrue);
    });

    test('a running window with no end time is refused before anything is sent',
        () async {
      final repository = _FakeCloseRepository();
      final result = await CloseSubmitter(repository).submit(
        _request(hasOpenWindow: true, noEnd: true),
      );

      expect(result, isA<CloseFailed>());
      expect(repository.calls, isEmpty);
    });

    test('downtime is written once, even when the close is retried', () async {
      final repository = _FakeCloseRepository(
        completeError: const HttpFailure(
          status: 422,
          message: 'Root-cause analysis is incomplete.',
          missing: ['rootCause'],
        ),
      );
      final submitter = CloseSubmitter(repository);

      final rejected = await submitter.submit(_request());
      expect(rejected, isA<CloseRejected>());
      expect((rejected as CloseRejected).needsRootCause, isTrue);

      repository.completeError = null;
      repository.calls.clear();
      final second = await submitter.submit(_request(rootCause: 'wear'));

      expect(second, isA<CloseSucceeded>());
      // The downtime PATCH already landed; only root cause and the close go out.
      expect(repository.calls, ['rca', 'complete']);
    });

    test('"already completed" is a success, not a failure to retry', () async {
      final repository = _FakeCloseRepository(
        completeError: const HttpFailure(
          status: 400,
          message: 'This work order has already been started or completed',
        ),
      );
      final result = await CloseSubmitter(repository).submit(_request());

      expect(result, isA<CloseAlreadyClosed>());
    });

    test('a 500 that already committed is reported as closed', () async {
      // workOrderController.ts completes the record and then throws on a line
      // referencing an undefined `status`.
      final repository = _FakeCloseRepository(
        completeError: const HttpFailure(
          status: 500,
          message: 'status is not defined',
        ),
        completedAfterwards: true,
      );
      final result = await CloseSubmitter(repository).submit(_request());

      expect(result, isA<CloseSucceeded>());
      expect(repository.calls, ['downtime', 'complete', 'verify']);
    });

    test('a 500 that did not commit is still a failure', () async {
      final repository = _FakeCloseRepository(
        completeError: const HttpFailure(
          status: 500,
          message: 'Database connection lost',
        ),
      );
      final result = await CloseSubmitter(repository).submit(_request());

      expect(result, isA<CloseFailed>());
      expect((result as CloseFailed).message, 'Database connection lost');
    });

    test('a checklist gate comes back as the server named it', () async {
      final repository = _FakeCloseRepository(
        completeError: const HttpFailure(
          status: 422,
          message: 'Complete at least one checklist item first.',
          missing: ['checklist'],
        ),
      );
      final result = await CloseSubmitter(repository).submit(_request());

      expect(result, isA<CloseRejected>());
      expect((result as CloseRejected).needsChecklist, isTrue);
      expect(result.needsRootCause, isFalse);
    });
  });
}
