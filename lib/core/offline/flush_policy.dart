/// What [SyncClient.flushQueue] does with one queued mutation the server
/// answered with an error. Pulled out as pure functions so the rules that
/// decide whether a technician's evidence is kept or dropped are unit-tested
/// on their own, without a database or a network.
enum FlushOutcome {
  /// Stop the whole run and keep everything queued. Every mutation behind
  /// this one would fail the same way until something outside the queue
  /// changes (a fresh GPS fix, a new sign-in), so dropping them would lose
  /// work that is perfectly valid.
  stopRun,

  /// The server rejected this one for good (a 4xx, or out of retries). Move
  /// it to the conflict log and carry on with the next.
  drop,

  /// A server-side hiccup (5xx) with attempts left. Keep it and move on.
  retryLater,
}

FlushOutcome classifyFlushFailure({
  required int status,
  required int attemptsSoFar,
  required int maxAttempts,
}) {
  // 428 — the location gate (see `middleware/auth.ts`): fixed by a check-in.
  // 401 — the session expired: fixed by signing in again. FR-4.4 makes this
  // one matter: a background run can start hours after the 24h session
  // lapsed, with nobody there to sign in, and treating it as an ordinary
  // 4xx would silently move a whole shift's checks into "could not be saved".
  if (status == 428 || status == 401) return FlushOutcome.stopRun;

  final attempts = attemptsSoFar + 1;
  if (attempts >= maxAttempts || (status >= 400 && status < 500)) {
    return FlushOutcome.drop;
  }
  return FlushOutcome.retryLater;
}

/// FR-4.4 — a short-lived "I'm uploading" marker in `sync_meta`, so the app
/// and a background WorkManager run (a separate Flutter engine on Android)
/// never replay the queue at the same time. Replaying a check twice is safe,
/// since the server's idempotency guard dedupes on the mutation id. Uploading
/// its photos twice is not: each upload mints a new file. So the queue has one
/// drainer at a time.
///
/// It's a lease rather than a plain flag, so a run that dies mid-flush (the
/// OS kills the background engine) can't lock the queue forever. The holder
/// renews it after every item.
class SyncLease {
  const SyncLease({required this.owner, required this.expiresAt});

  final String owner;
  final DateTime expiresAt;

  static const ttl = Duration(minutes: 3);

  /// `owner|expiresAtMs` — stored as one `sync_meta` value.
  String encode() => '$owner|${expiresAt.millisecondsSinceEpoch}';

  static SyncLease? decode(String? raw) {
    if (raw == null) return null;
    final bar = raw.lastIndexOf('|');
    if (bar <= 0) return null;
    final ms = int.tryParse(raw.substring(bar + 1));
    if (ms == null) return null;
    return SyncLease(
      owner: raw.substring(0, bar),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// [owner] may take (or renew) the lease if nobody holds it, it has
  /// expired, or [owner] already holds it.
  static bool canTake(SyncLease? current, String owner, DateTime now) =>
      current == null ||
      current.owner == owner ||
      !current.expiresAt.isAfter(now);
}
