import 'package:flutter_test/flutter_test.dart';
import 'package:technician_portal/core/offline/flush_policy.dart';

void main() {
  group('classifyFlushFailure — what happens to a queued check the server refused', () {
    FlushOutcome classify(int status, {int attempts = 0}) =>
        classifyFlushFailure(
          status: status,
          attemptsSoFar: attempts,
          maxAttempts: 5,
        );

    test(
      '401 (session expired) stops the run and keeps the check — FR-4.4',
      () {
        expect(classify(401), FlushOutcome.stopRun);
      },
    );

    test('401 keeps the check even when it is on its last attempt', () {
      expect(classify(401, attempts: 4), FlushOutcome.stopRun);
    });

    test('428 (location gate) stops the run and keeps the check', () {
      expect(classify(428), FlushOutcome.stopRun);
    });

    test(
      'an ordinary 4xx is a real rejection and is dropped to the conflict log',
      () {
        expect(classify(400), FlushOutcome.drop);
        expect(classify(403), FlushOutcome.drop);
        expect(classify(404), FlushOutcome.drop);
      },
    );

    test('a 5xx with attempts left is retried later', () {
      expect(classify(500, attempts: 0), FlushOutcome.retryLater);
      expect(classify(503, attempts: 3), FlushOutcome.retryLater);
    });

    test('a 5xx out of attempts is dropped', () {
      expect(classify(500, attempts: 4), FlushOutcome.drop);
    });
  });

  group(
    'SyncLease — one drainer at a time across the app and background engine',
    () {
      final now = DateTime(2026, 9, 25, 12);

      test('round-trips through its stored form', () {
        final lease = SyncLease(owner: 'abc-123', expiresAt: now);
        final back = SyncLease.decode(lease.encode())!;
        expect(back.owner, 'abc-123');
        expect(back.expiresAt, now);
      });

      test('garbage in storage reads as no lease rather than a crash', () {
        expect(SyncLease.decode(null), isNull);
        expect(SyncLease.decode('nonsense'), isNull);
        expect(SyncLease.decode('owner|notanumber'), isNull);
      });

      test('free when nobody holds it', () {
        expect(SyncLease.canTake(null, 'app', now), isTrue);
      });

      test('someone else holding a live lease blocks you', () {
        final held = SyncLease(
          owner: 'background',
          expiresAt: now.add(const Duration(minutes: 1)),
        );
        expect(SyncLease.canTake(held, 'app', now), isFalse);
      });

      test('the holder can renew its own lease', () {
        final held = SyncLease(
          owner: 'app',
          expiresAt: now.add(const Duration(minutes: 1)),
        );
        expect(SyncLease.canTake(held, 'app', now), isTrue);
      });

      test(
        'an expired lease (its holder was killed mid-run) can be taken over',
        () {
          final stale = SyncLease(
            owner: 'background',
            expiresAt: now.subtract(const Duration(seconds: 1)),
          );
          expect(SyncLease.canTake(stale, 'app', now), isTrue);
        },
      );
    },
  );
}
