# Pending

Work this repo still owes: unfinished, partly done, blocked, or built but never verified. Companion to [LEARNINGS.md](LEARNINGS.md). LEARNINGS records what we learned and only grows. This file is a live list: items leave it when they are done.

**The 2026-09-25 audit findings stay in [docs/improvements.md](docs/improvements.md)** with their own `#` numbers. Don't copy them here; mark them done there when fixed. This file holds everything else: session leftovers, deferred work, things not verified.

- **Add** an item before ending any turn that leaves work owed. Take the number from "Next number" below and bump it. Never reuse a number.
- **Close** an item by moving it to Closed as one line: date, how it was resolved, and its LEARNINGS entry.
- **Status:** `not started` · `partial` · `blocked` · `needs verification` (built, but `flutter analyze`/`flutter test` on Flutter ≥ 3.44 or a device run not done)
- **Priority:** P1 loses field work or shows the technician something false · P2 real feature gap · P3 cleanup
- **Cross-repo:** the item lives in the repo that owns the fix. The other repo gets a one-line pointer.
- **Sweep and re-verify everything:** run `/pending-sweep` from the workspace root.

<!-- Entry template
### P-000 · <one-line title>
- **Status:** not started · **Priority:** P2 · **Area:** <module>
- **Found:** YYYY-MM-DD (<source: LEARNINGS entry, doc, session>)
- **Done so far:** <what exists already, or —>
- **Left:** <what is still owed>
- **Why deferred:** <out of scope / blocked on X / needs decision>
- **Where:** <path:line, path:line>
- **Next step:** <the first concrete action>
-->

Next number: **P-004**

## Open

### P-003 · Three existing tests fail on unmodified HEAD
- **Status:** not started · **Priority:** P3 · **Area:** tests
- **Found:** 2026-09-26 (first real `flutter test` run on Flutter 3.47.5; reproduced on a `git archive HEAD` copy)
- **Done so far:** reproduced on unmodified HEAD, so these failures come from the existing code, not from the Snag Assistant.
- **Left:**
  - (1) `dates_test` "isOverdueDate ignores earlier today" fails when run just after midnight, so it depends on the clock.
  - (2) `qr_payload_test` "one of our own public pages is offered as a record" fails and needs a look at its `Env.webBaseUrl` assumption.
  - (3) every `order_detail_test` "per-type headings" case hangs until its 10-minute timeout inside `_localizedContext` (`FlutterLocalization.ensureInitialized()` with no `SharedPreferences.setMockInitialValues`). This alone adds about 40 minutes to a full run.
- **Why deferred:** outside the Snag Assistant's scope.
- **Where:** [test/dates_test.dart](test/dates_test.dart), [test/qr_payload_test.dart](test/qr_payload_test.dart), [test/order_detail_test.dart:25](test/order_detail_test.dart#L25)
- **Next step:** add `SharedPreferences.setMockInitialValues({})` to `_localizedContext` and re-run (3). Pin a fixed `now` in (1).

### P-001 · Snag Assistant: never run on a device
- **Status:** needs verification · **Priority:** P2 · **Area:** Snag Assistant (`lib/features/snags/`)
- **Found:** 2026-09-26 (Snag Assistant build)
- **Done so far:** the full module, shown in [docs/snag-assistant.md](docs/snag-assistant.md). `dart analyze` is clean, and `flutter test` passes for the 39 snag tests (rules, model, widgets, and hub/detail/survey screens in EN and AR at 360 px). Both ran on Flutter 3.47.5, bootstrapped into the session scratchpad (LEARNINGS → Platform).
- **Left:** a device run of walk mode (live `CameraController` across 30+ shots, torch, backgrounding), the ghost camera, voice notes, the room picker on a real building tree, and offline → online replay of a full walk against a server with `findings:promote` applied. Walk, raise, verify and ghost-camera screens have no widget tests, because they need the camera plugin.
- **Why deferred:** there is no Android device or emulator on this Mac, and the server migration is not applied (server PENDING P-010).
- **Where:** [snag_walk_screen.dart](lib/features/snags/snag_walk_screen.dart), [ghost_camera_screen.dart](lib/features/snags/ghost_camera_screen.dart), [snag_repository.dart](lib/data/snag_repository.dart)
- **Next step:** apply server P-010, then run a 20-snag walk in airplane mode, go online, and check the Sync Center drains and the hub loses its "On device" badges.

### P-002 · Snag Assistant: logout wipes unsynced snags, like the queue
- **Status:** not started · **Priority:** P1 · **Area:** Snag Assistant / offline
- **Found:** 2026-09-26 (Snag Assistant build)
- **Done so far:** `OfflineDb.wipe()` clears `snags` and `snag_surveys` together with the queue, which is consistent with improvements.md's queue-wipe P1.
- **Left:** fix together with that P1. A surveyor whose 24h session expires mid-walk loses every snag not yet synced (the photo files under `snag_media/own/` survive, but nothing points at them).
- **Why deferred:** the fix belongs to the platform-wide queue-wipe item, not to this module.
- **Where:** [offline_db.dart](lib/core/offline/offline_db.dart) `wipe()`
- **Next step:** when improvements.md's logout P1 is fixed, keep `local_only=1` snag rows and their surveys through a re-login by the same user.


## Closed

_None yet._
