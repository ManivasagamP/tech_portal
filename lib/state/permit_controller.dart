import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/permit_repository.dart';
import '../domain/permit.dart';
import 'auth_controller.dart';
import 'providers.dart';

/// Permit to Work state (docs/permit-to-work.md). Hand-written providers, no
/// codegen, same style as the rest of `state/`. Unlike Snag Assistant there
/// is no local write-ahead store or tick provider to bump: every screen just
/// re-reads [PermitRepository] (cache-then-network on the way in, a fresh
/// server copy cached back in on the way out of a write — see the
/// repository's doc comment), so `ref.invalidate` after a write is enough.

final permitRepositoryProvider = Provider<PermitRepository>(
  (ref) => PermitRepository(sync: ref.watch(syncClientProvider)),
);

final permitCatalogProvider = FutureProvider<PermitCatalog>(
  (ref) => ref.watch(permitRepositoryProvider).catalog(),
);

/// The signed-in technician's id, for `PermitDetail.myCrew`/`canRestore` —
/// null before login finishes, same guard `snagActorProvider` uses.
final permitSessionUserIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authControllerProvider).session;
  return (session == null || session.userId.isEmpty) ? null : session.userId;
});

/// One row of "My permits" plus whether it came from the crew query — the
/// nearest this app can get to "am I on this permit's crew" without a
/// dedicated field, since `PermitSummary` (unlike `PermitDetail.crew`)
/// carries no per-technician sign-on state. See [PermitHubItem.needsSignature].
class PermitHubItem {
  const PermitHubItem({required this.summary, required this.isCrew});
  final PermitSummary summary;
  final bool isCrew;

  /// Approximation of "I'm crew and haven't signed on yet": true whenever
  /// this technician is listed as crew on a live permit. It cannot tell
  /// apart "I haven't signed on" from "I signed on, someone else hasn't" —
  /// that needs `PermitDetail.myCrew`, which only the detail screen has. A
  /// false positive here just means an extra reminder badge on a permit the
  /// technician already signed onto; see docs/permit-to-work.md §6 and
  /// PENDING for the contract addition that would make this exact.
  bool get needsSignature => isCrew && summary.isLive;
}

/// "My permits" — the crew list and the raised list merged into one (a
/// permit the technician both requested and is crew on appears once), live
/// permits first. Among live permits the soonest to expire sorts first (the
/// one that most needs attention); among done ones, most recently updated
/// first.
final myPermitsProvider = FutureProvider<List<PermitHubItem>>((ref) async {
  final repo = ref.watch(permitRepositoryProvider);
  final lists = await Future.wait([repo.mine('crew'), repo.mine('raised')]);
  final crewIds = lists[0].map((p) => p.id).toSet();
  final byId = <String, PermitSummary>{};
  for (final list in lists) {
    for (final p in list) {
      byId[p.id] = p;
    }
  }
  final merged = byId.values.toList()
    ..sort((a, b) {
      final liveRank = (b.isLive ? 1 : 0).compareTo(a.isLive ? 1 : 0);
      if (liveRank != 0) return liveRank;
      if (a.isLive && b.isLive) {
        final av = a.validUntil ?? a.plannedEnd ?? a.createdAt;
        final bv = b.validUntil ?? b.plannedEnd ?? b.createdAt;
        return av.compareTo(bv);
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
  return [for (final p in merged) PermitHubItem(summary: p, isCrew: crewIds.contains(p.id))];
});

final permitDetailProvider = FutureProvider.family<PermitDetail?, String>(
  (ref, id) => ref.watch(permitRepositoryProvider).detail(id),
);

/// A worksite-QR scan (`Routes.permitByToken`'s resolver screen).
final permitByTokenProvider = FutureProvider.family<PermitDetail?, String>(
  (ref, token) => ref.watch(permitRepositoryProvider).byToken(token),
);

/// Call after any write completes — synced or only queued — so the detail
/// screen and the hub both re-read: the server's fresh copy when it synced,
/// or the same cached copy as before when it only queued (there is nothing
/// newer to show until it does; see `PermitRepository`'s doc comment).
void refreshPermit(WidgetRef ref, String id) {
  ref.invalidate(permitDetailProvider(id));
  ref.invalidate(myPermitsProvider);
}
