# LEARNINGS — FusionEco FieldOps

Durable lessons for this repo: bug patterns and their root causes, "don't do X because Y", contracts that aren't obvious from the code. **Append, don't rewrite.** Put each entry under its domain header, newest first. Format:

```
### <short title> (YYYY-MM-DD)
**What happened:** … **Cause:** … **Fix:** … **What to watch:** … (with a concrete example)
**Where:** file:line / commit · **Project state:** (when it matters)
```

Entries marked **Source:** were carried over on 2026-09-25 from `fusion-eco-server/LEARNINGS.md` and `fusion-eco-client/LEARNINGS.md`, because they bind this app. The originals hold the full story.

**Project state when this file was created (2026-09-25):** `main` @ `8b60a07`, version `1.0.1+3`, Android-only release (package `com.fusionapps.fieldops`). `flutter analyze` and `flutter test` were **not** run: this Mac's newest Flutter is 3.19.3 and the lockfile needs Flutter ≥ 3.44 / Dart ≥ 3.13.2. The prioritized open issues are in [docs/improvements.md](docs/improvements.md).

---

## Offline queue and sync

### Logging out deletes the unsynced queue (2026-09-25, open)
**What happened:** An audit found that `AuthController.logout()` calls `OfflineDb.wipe()`, which deletes `pending_mutations` and drafts. `logout()` runs on manual sign-out, the in-app 24h expiry timer, the session-expired dialog and **any 401**. **Cause:** the wipe has been there since the first scaffold (`82ab613`, 2026-09-07). Background sync (`8b60a07`) was later written on the assumption that "the queue is kept; it drains next sign-in". **Fix:** not fixed yet; see improvements #1. **What to watch:** a technician whose 24h session lapses while the app is open loses the whole shift's queued checks. If the session lapses while the app is *closed*, the queue survives and replays under whoever signs in next.
**Where:** `lib/state/auth_controller.dart:116-125`, `lib/core/offline/background_sync.dart:112`

### Replays are de-duplicated only for successes; uploads never are (2026-09-25)
**What happened:** The `X-Client-Mutation-Id` contract existed only in code on both sides. No doc recorded it. **Cause / contract:** the server's `middleware/idempotency.ts` caches **2xx** responses under `idem:<id>` for 24h and answers a repeat with the stored body plus `X-Idempotent-Replay: true`. Failures are not cached, so replaying a 4xx or 5xx runs the request again. There is no de-dupe if Redis is down, and every upload mints a new file. **Fix:** the app mints the id once at capture time and reuses it on every replay (`api_client.dart:36`, `sync_client.dart:185`). The flush lease keeps two engines from uploading the same photos. **What to watch:** never mint a fresh mutation id on retry. Never let two flushers run at once. A field that applies a change (stock, counters) is not safe to replay after a 4xx.
**Where:** `lib/core/network/api_client.dart:11-39`, server `src/middleware/idempotency.ts:22-61`

### Background engine: never mint a passphrase, never close the DB (2026-09-25)
**What happened:** WorkManager background sync (FR-4.4) runs `SyncClient` in a second Flutter engine that shares the SQLCipher file with the app. **Cause:** a background run creating its own passphrase would make the real DB unreadable. `db.close()` in one engine pulls the shared native connection out from under the other. **Fix:** use `readDbPassphrase()` (read-only), return early if there is no token or no passphrase, leave the DB open, and use a `SyncLease` in `sync_meta` (3-min TTL, renewed after each item) so only one engine drains. **What to watch:** anything else that ever runs headless (a push handler that writes to the DB, for example) must follow the same three rules.
**Where:** `lib/core/offline/background_sync.dart:108-143`, `lib/core/offline/flush_policy.dart:39-78`

### 428 and 401 during a flush must stop the run, not drop items (2026-09-23)
**What happened:** A stale GPS fix (428) or an expired session (401) would have failed every queued item in turn. Each one would have been classified as a 4xx and moved to "could not be saved". **Cause:** the server rejects every mutating request until something outside the queue changes. **Fix:** `classifyFlushFailure` returns `stopRun` for 428 and 401 and keeps the queue. `CheckInController.checkIn()` resumes the flush after a fix lands. **What to watch:** any new "precondition" status the server adds belongs in `stopRun`, not `drop`. Also see the open issue above: the 401 *also* triggers logout, which wipes the queue anyway.
**Where:** `lib/core/offline/flush_policy.dart:20-37`, `lib/core/offline/sync_client.dart:356-390`, `lib/state/checkin_controller.dart:67-71`

### Connectivity events are not a reliable wake-up (2026-09-23)
**What happened:** Tested on a device: the queue never drained after signal came back. **Cause:** `connectivity_plus` `onConnectivityChanged` can fail to emit a clean offline→online transition when a low-capability network (an IMS-only mobile radio) lingers through the outage. **Fix:** a 20s poll in `startAutoFlush` as a backstop, a flush on app resume, and WorkManager's network-constrained job. **What to watch:** don't remove the poll because "the stream handles it". `flushQueue` is cheap to no-op.
**Where:** `lib/core/offline/sync_client.dart:112-132`, `lib/features/shell/technician_shell.dart:71`

### Retrying one queued item must reuse the normal flush logic (2026-09-07)
**What happened:** Sync Center needed a per-item "Sync now". **Cause:** the web first wrote a separate `syncOne` that skipped ordering and locking. **Fix (here):** `flushQueue(stopAfterId:)` drains oldest-first *up to* that item, under the same lock and lease. **What to watch:** don't add a second replay path. Two paths drift, and a single-item replay that jumps the queue breaks RCA → downtime → complete ordering.
**Where:** `lib/core/offline/sync_client.dart:280-290`, `lib/features/sync/sync_center_screen.dart:39-45` · **Source:** client LEARNINGS "Offline-sync view all + per-item resync (2026-09-07)"

### One wording for every queued write (2026-09-08)
**What happened:** Each call site worded the offline toast differently ("Note saved offline…", "Photo saved offline…"). Technicians read them as different events. **Fix:** a single `kOfflineQueuedMessage`. **What to watch:** only show it when the write is actually in `pending_mutations`. The inspection form currently shows it for uploads held only in widget memory (improvements #6).
**Where:** `lib/core/offline/sync_client.dart:24`

### QueueBus must emit a fresh value every time (2026-09-07)
**What happened:** Queue-driven lists stopped refreshing after the first change. **Cause:** a stream of a constant value collapses into an equal `AsyncValue`, and Riverpod stops notifying dependents. **Fix:** emit an incrementing tick. **What to watch:** the same applies to any "something changed" stream feeding a `StreamProvider`.
**Where:** `lib/core/offline/queue_bus.dart:10-17`

### Background prefetch needs an in-flight flag, not just a timestamp (2026-08-31)
**What happened (web):** Opening a work order fired about 10 identical request batches. **Cause:** `prefetchOfflineBundle` checked a `lastPrefetchAt` it read asynchronously and wrote only after finishing, so two callers both passed the check. **Fix (web):** a module-level `prefetching` flag set before the first async read. **What to watch:** the Dart `prefetch.dart` has the **same timestamp-only guard** and can be called from the dashboard and from Profile. Add a flag if duplicate manifest calls show up.
**Where:** `lib/core/offline/prefetch.dart:35-42` · **Source:** client LEARNINGS "Offline prefetch fired duplicate request batches (2026-08-31)"

---

## Auth, session and location gate

### Location check-in: login flag plus a 428 gate on writes only; there is no silent push (2026-09-15)
**What happened:** The first server design sent a 05:00 silent FCM push (`{type:"location_request"}`) that the app should answer with a GPS fix. The same day it was replaced by a login-time check. **Contract:** `POST /api/auth/technician-login` returns `requestLocation: true` when the last fix is missing or older than 24h. Every technician POST/PUT/PATCH/DELETE with a stale fix gets `428 {code:"LOCATION_REQUIRED"}`. GET and HEAD are never gated, and neither are routes using `optionalDecodeToken`. There are **three** exemptions: `POST /fm/technicians/me/location`, `POST /c2o/assets/:id/verify` and `POST /fm/assets/:id/tag-issue` (server `middleware/auth.ts:35-39`; the server doc lists only the first). **Fix (here):** `Session.requestLocation` → `CheckInController` → the full-screen `LocationCheckInGate` → `POST /api/fm/technicians/me/location {lat,lng}` → resume the flush. **What to watch:** don't build a `location_request` push handler; that server LEARNINGS note is obsolete. `LocalNotifications.show` draws *every* data message, so a reinstated silent push would appear as a blank "Fusion Eco" banner.
**Where:** `lib/state/checkin_controller.dart`, `lib/widgets/location_checkin_gate.dart`, `lib/core/network/api_client.dart:46` · **Source:** server LEARNINGS 2026-09-15 (and follow-ups 1–4)

### Settings flags come from one Redis schema; keys it doesn't list vanish (2026-09-09)
**What happened (server):** A flag saved OK but never came back. **Cause:** `ConfigSchema` (server `common/redis.ts`) silently drops keys it doesn't list, on both save and read. `GET /api/auth/config` returns that raw object, not wrapped in `data`. **What to watch:** every flag this app reads (`isAiAgent`, `isCreateAsset`, `isAssetReport`, `isDigitalTwin`, `currencyType`, `currencyRates`) must exist in that schema. `isDigitalTwin` is nullable and opt-out: only an explicit `false` hides 3D. `currencyType` is a symbol ("₹"), not an ISO code.
**Where:** `lib/core/storage/session_store.dart:111-162` · **Source:** server LEARNINGS 2026-06-11 and 2026-09-09

### An unapplied DB column breaks login on a fresh environment (2026-09-15)
**What happened (server):** `technician-login` threw `column "lastLocationLat" does not exist`. **Cause:** the server never auto-runs `npm run sync` (DB-safety rule). **What to watch:** if login or a screen suddenly returns 500 on one tenant after a server update, suspect a missing column (`lastLocation*`, `ai_chat_messages.audio`, `c2o_route_assignments`) before debugging the app.
**Source:** server LEARNINGS 2026-09-15 follow-up 4 and 2026-09-20

---

## Push and notifications

### Pushes are data-only, so the app must draw them itself (2026-09-08)
**What happened:** Nothing appeared and no sound played when a push arrived in the background. **Cause:** the server sends data-only messages `{title, link, entityId, entityType}` with no body, and the OS shows nothing for those. **Fix:** a top-level `@pragma('vm:entry-point')` background handler re-inits Firebase and `LocalNotifications.show()` posts the notification on channel `fcm_default_channel` with the `notification_ting` raw sound. **What to watch:** Android fixes a channel's sound when the channel is created, so a new sound needs a **new channel id**. The tray shows only the title; the full text lives in the in-app list. The device token is deliberately **not** unregistered on logout (phones are personally issued), so a signed-out phone still gets the last user's titles.
**Where:** `lib/core/push/push_service.dart:12-24`, `lib/core/push/local_notifications.dart:14-20` · **Source:** server LEARNINGS "FCM push (Flutter technician app) (2026-09-07)"

### A `link` wins over entity routing, and only `/technician/*` links resolve (2026-09-12)
**What happened (web):** A technician's SLA warning would have opened the admin page. **Cause:** notification routing returns `link` before checking `entityType`, and the server's `slaLink()` built an admin path. **Fix (server):** technician copies carry no `link` and route by `entityType`. **What to watch:** this app returns *no route* for a link outside `/technician`, so a server helper that adds an admin `link` makes the tap silently do nothing. The rules exist twice: `routeForNotification` and `_routeForPushData`. Change both.
**Where:** `lib/core/utils/notification_route.dart:10-42`, `lib/core/push/push_service.dart:99-131` · **Source:** client LEARNINGS "SLA v2 client — a link field silently overrides role-based routing (2026-09-12)"

### Invite notifications open the invites inbox, matched by exact title (2026-08-31)
**What happened (web):** Tapping "New assignment invite" opened the heavy detail page and caused a burst of API calls. **Fix:** route the exact title `"New assignment invite"` (the only title `assignmentInviteService.ts` uses) to the invites tab. **What to watch:** renaming that title on the server silently breaks routing here.
**Where:** `lib/core/utils/notification_route.dart:29-32` · **Source:** client LEARNINGS 2026-08-31

---

## Maintenance orders: checklists, close, invites, AI chat

### The server removed the reactive and annual write routes; the app still calls them (2026-09-12, open here)
**What happened (server):** Annual Maintenance became a read-only view of PM plans (`/analytics`, `/building-compliance`, `/`, `/:id` only). Reactive tickets now generate a work order (`sourceRmId`), and RM `/checklist`, `/time-tracking` and `/status` were deleted. **What to watch (here):** `OrderType.reactive`/`annual` still point `checklistPath`/`completePath` at those routes. Online they 404; offline they queue and are later dropped. `listInvites` still requests `/api/fm/annual-maintenance/technician/:id`, and the 404 is swallowed. Lists, dashboard and calendar already follow the change (work orders only). Before deleting a per-id screen, grep **every** inbound link: notification routing, push routing, QR payloads, invites.
**Where:** `lib/domain/maintenance_record.dart:30-50`, `lib/data/orders_repository.dart:39-67`, improvements #5 · **Source:** server LEARNINGS 2026-09-12 (both entries)

### The signature is a flagged checklist item, required on every close, and rides the queue (2026-09-09)
**Contract:** a signature is item `{id:"signature-<ts>", isOther:true, isSignature:true, isCompleted:true, signatureUrl, signerName, signedAt}` appended to `checklists`. The server's `checklistCloseGuard.ts` returns `422 missing:["signature"]` on every close without one. **Fix (here):** the PNG goes as a `QueuedAttachment` with a `__pending_signature_…__` placeholder inside a whole-record `PUT`, sent before the completion call. **What to watch:** don't "just upload" it directly, because that loses the offline guarantee. When reshaping any flagged item, carry every field (the web lost `isSignature` in five handlers). Whole-record PUTs built from the cached `record.raw['checklists']` can overwrite queued item writes on replay (improvements #3).
**Where:** `lib/data/checklist_repository.dart:263-357`, `lib/features/order_detail/close_sheet.dart:187-226` · **Source:** server/client LEARNINGS "Technician digital signature (2026-09-09)"

### Voice-only send was blocked by three separate checks (2026-09-09)
**What happened:** A voice note with no text couldn't be sent in the Order Assistant. **Cause:** the server returned 400 on an empty `message`. In Flutter, the send button enabled correctly on `hasContent`, but `_send()` re-checked `text.trim().isEmpty` and `ChatController.send()` re-checked `message.isEmpty`. **Fix:** the server accepts text OR audio OR images, and both Flutter checks were relaxed to `hasContent`. **What to watch:** a button that looks enabled can be dead if its handler re-derives a stricter check. Check every layer down to the network call. New attachment kinds must also come back from `GET /api/fm/ai/chat/history`, or they vanish on reopen.
**Where:** `lib/features/order_detail/order_chat_sheet.dart`, `lib/state/chat_controller.dart` · **Source:** server LEARNINGS 2026-09-09 (both voice entries)

### A reactive ticket's lowercase priority hid the root-cause field (pre-2026-09-25)
**What happened:** Critical reactive tickets got `422 rootCause` with no root-cause field on screen. **Cause:** RM stores priority lowercase and the others capitalise it, and the check compared strictly. **Fix:** a case-insensitive `rcaRequiredForPriority`. `_forceRcaVisible` also shows the field whenever the server names `rootCause`, because the server's 422 beats the client's guess. **What to watch:** field shapes differ by record type. Done is `Completed` for WO/RM and `completed` for PM. The technician field is `assignedTechnician` (an id) on WO and `technicianId` elsewhere (RM's `assignedTechnician` is a display name). Normalise case on every cross-type comparison.
**Where:** `lib/domain/downtime.dart:69-78`, `lib/features/order_detail/close_sheet.dart:90-98` · **Source:** server LEARNINGS "ENUM casing differs per table (2026-08-08)"

### A close that committed but answered 500 was reported as failed (pre-2026-09-25)
**What happened:** The technician was told the close failed, but the record was already closed. **Cause:** server `workOrderController.ts` completed the record, then threw on an undefined `status`. **Fix:** on a 5xx from complete, fetch the record and check `completedDate`/`status` before reporting a failure. A retry's 400 "already completed" counts as success (`HttpFailure.isAlreadyCompleted`). **What to watch:** "the request failed" doesn't mean "nothing was written". The flush path doesn't apply `isAlreadyCompleted` yet, so a replayed duplicate close lands in conflicts (improvements #4).
**Where:** `lib/state/close_controller.dart:158-169`, `lib/data/close_repository.dart:75-90`, `lib/core/network/api_exception.dart:40-45`

### Downtime was re-sent when a close was retried (pre-2026-09-25)
**What happened:** A 422 on complete followed by a retry sent the downtime PATCH twice. **Fix:** `_downtimeHandled` lives on the `CloseSubmitter`, one per open sheet, and a test pins it ("downtime is written once, even when the close is retried"). **What to watch:** creating a new `CloseSubmitter` per tap brings the bug back. Downtime is a single `PATCH /api/fm/downtime/:source/:id {startedAt, endedAt, impact}`. When pre-filling from `GET /api/fm/assets/:id/downtime`, match on `source`/`sourceId` and ignore rows with `derived: true`.
**Where:** `lib/state/close_controller.dart:88-97`, `lib/features/order_detail/close_sheet.dart:47` · **Source (contract):** server/client LEARNINGS "downtime_logs removed (2026-08-08)"

### A form field that gets locked must not be pre-filled from the cache (pre-2026-09-25)
**What happened:** The close sheet pre-filled and locked a downtime start from a window that had already been closed. **Cause:** downtime history was read through `syncGet`'s cache. **Fix:** read it with plain `ApiClient`, return `[]` on error, and make the provider `autoDispose`. **What to watch:** anything that *locks* a field must read live data.
**Where:** `lib/data/close_repository.dart:10-32`, `lib/state/close_controller.dart:199-205`

### A cached detail first undid offline writes, then blanked the checklist (pre-2026-09-25)
**What happened:** A cached refetch after an offline write replaced the local list and undid the write. The guard added for that then refused the cache on a cold start, so a real job showed "No checklist items". **Fix:** a cached detail may seed the list only when no local state exists yet. **What to watch:** any provider that mixes server truth with optimistic local patches (for example, an offline photo add followed by pull-to-refresh).
**Where:** `lib/state/checklist_controller.dart:61-84`

### "Other" checklist items need a unique `id` (2026-08-31)
**What happened (web):** Deleting one id-less "Other" item deleted all of them (`undefined !== undefined` is false). **Fix:** ids are `other-<ms>-<7 chars of uuid>`. **What to watch:** every item appended to `checklists` needs a unique id; `signature-<ms>` is unique only per millisecond. `sessions[]` is saved exactly as sent. Sending `faceCaptureUrl` with both `startTime` and `endTime` puts the image in the wrong slot.
**Where:** `lib/data/checklist_repository.dart:281-284` · **Source:** client LEARNINGS 2026-08-31, 2026-07-23

### Close checks answer with 422 `missing[]`; the client's checks are only UX (2026-08-07)
**Contract:** every completion path runs `assertCloseAllowed` and `checklistCloseGuard`, and returns `422 {missing:[…]}` with `checklist`, `signature`, `session` or `rootCause` (Critical/High, case-insensitive). `failureCodeId` is never produced; that feature never existed. The RCA endpoint is `POST /api/fm/{work-orders|preventive-maintenance|reactive-maintenance}/:id/rca {rootCause, rcaNotes}`. Note the **plural** `work-orders` here. **What to watch:** never show an error against a field that isn't on screen. Never wrap a new endpoint in an "empty list on error" fallback without confirming it exists; a swallowed 404 kept a dead failure-code picker alive through three audits.
**Where:** `lib/core/network/api_exception.dart:26-30`, `lib/state/close_controller.dart:66-73` · **Source:** server/client LEARNINGS 2026-08-07 and 2026-08-08

### Declining an invite passes the job along; PM invites must stay reachable (2026-09-02)
**Contract:** respond with `POST /api/fm/{work-order|preventive-maintenance|reactive-maintenance}/:id/assignment/respond {action, reason?}`. A decline moves the job to the next technician in `assignmentChain`, and only an exhausted chain returns to `pending`. The record is never cancelled. **What to watch:** don't treat a decline as final in local state. Preventive maintenance is hidden from the orders list but must stay in the invite fan-out, because its invite is the only way to reach a PM detail page.
**Where:** `lib/data/orders_repository.dart:47-67` · **Source:** server LEARNINGS 2026-09-01/02, client LEARNINGS 2026-08-31

### Work starts from checklist activity, not a button (2026-08-30)
**What happened (web):** A manual "Start Work" button was built and then removed within hours. **Cause:** the server sets In Progress when the first checklist timer starts, and `startedDate` is the earliest session start. **What to watch:** before building any start/stop UI, check what the server already derives. `core/utils/checklist_status.dart` is a port of web `lib/checklist-status.ts` and server `checklistCloseGuard.ts`; change all three together.
**Where:** `lib/core/utils/checklist_status.dart:6-7` · **Source:** client LEARNINGS 2026-08-30

---

## C2O field verification and routes

### The route release warning lives on the phone because the server can't see the queue (2026-09-25)
**What happened:** FR-5.8 wanted "don't hand a route over while the old technician still has unsent checks". Those checks exist only in this app's queue. **Fix:** the server exposes `lastUploadAt` per assignment. The release dialog counts this phone's queued checks ("3 checks still on this phone") and warns without blocking. Checks queue against the asset, not the route, so they still upload after a hand-off. **What to watch:** release is deliberately **not** queued: a release that lands hours late leaves the route unwalked and nobody knows. Flush first, then release online.
**Where:** `lib/features/routes/route_list_screen.dart:271-300`, `lib/data/route_assignment_repository.dart:20-31` · **Source:** server LEARNINGS 2026-09-25 (FR-5.8)

### C2O endpoints use two envelope shapes (2026-09-25)
**Contract:** `c2oRoutes` and the progress routes wrap `{success,data,message}`. `c2oExtendedRoutes` (route assignments, `/mine`) return bare bodies. Errors come back as `{success:false,message}`. **What to watch:** parse through `envelope.dart`'s `unwrap`/`unwrapMap`. "Everything pending, nothing moves" usually means an envelope mismatch.
**Source:** client LEARNINGS 2026-09-25

### A tokenless tag must never hit the public verify route (pre-2026-09-25)
**What happened:** A general Asset label or bare barcode sent to `/public/verify` gets a 403, which would show as a red "token mismatch". **Cause:** those formats never carry a token, and tag tokens are HMACs the server computes (`JWT_SECRET`, 16 hex characters); the phone never computes them. **Fix:** an uncached target with no token returns null and falls through to the general scanner. **What to watch:** "try the server for anything uncached" is the wrong rule for bare barcodes. The printed-tag format (`{web}/public/c2o-verify/{assetId}?t=…`) can't be reissued, so the parser and the server's `buildScanPayload` must stay in step.
**Where:** `lib/core/c2o/c2o_asset_resolver.dart:82-88`, `lib/core/c2o/c2o_scan_payload.dart` · **Source (format):** server LEARNINGS 2026-07-28

### Thin search rows must never be written into the scan cache (pre-2026-09-25)
**What happened:** Manual search builds cache-shaped rows from assigned work orders, which carry little data. Writing them into `c2o_assets` would permanently shadow real scan data, because the cached copy wins later merges. **Fix:** the detail screen fetches `GET /api/fm/assets/:id` instead. **What to watch:** "cache what we just opened" optimisations. `claims` must keep the `{asset:{id,…}, history, openFindings}` wrapper.
**Where:** `lib/features/c2o_search/c2o_asset_search_screen.dart:248-257`, `lib/core/c2o/assigned_assets.dart:38-48`

### BIM assets may carry only `aimData` codes for location (2026-09-20)
**Contract:** assets imported from BIM/AIM can have null `floorData`/`spaceData`, with location only in `aimData.buildingCode`/`levelCode`/`spaceCodeSource`. `locationPath` keeps a level when either its name or its code exists. The machine-readable type is `aimData.assetTypeCode`; `identity.assetType` is a display name. For 3D, `ifcGlobalId` is the asset's real element, while `twinGlobalId`/`isPresentation` describe a stand-in to show. The app reads neither yet. **What to watch:** a screen reading only `floorData?.floorName` is blank for BIM assets. Never zoom a technician to a stand-in without saying so.
**Where:** `lib/core/c2o/asset_detail.dart:46-50` · **Source:** client LEARNINGS 2026-09-20 (three entries)

### Indoor GPS at `.high` accuracy never settles (pre-2026-09-25)
**What happened:** Location capture kept timing out in plant rooms. **Cause:** `.high` waits for a GPS-grade fix. **Fix:** `.medium` with a 10s limit, then fall back to the last known position. A geocoding failure never loses the coordinates. The check-in uses the same sequence on purpose. **What to watch:** "better GPS" changes under FR-3.9.
**Where:** `lib/core/capture/capture_services.dart:209-230`, `lib/core/location/checkin_location.dart:18-52`

### The voice recorder and live speech recognition can't share the mic on Android (pre-2026-09-25)
**What happened:** Auto-transcribing while recording produced about 0.14s of audio for a 4s clip. **Cause:** Android gives the microphone almost exclusively to one listener, and the recognizer only works on a live stream. **Fix:** the voice note is recording-only and notes stay typed. **What to watch:** verify by pulling the recorded file, not by looking at the UI. Separately, the field-verification clip never reaches the submission today (improvements #7).
**Where:** `lib/features/field_verification/voice_note_capture.dart:13-31`

### Capture-form autosave never switched on for a brand-new form (pre-2026-09-25)
**What happened:** With no prior draft, edits were never saved. **Cause:** `_draftLoaded` was set only in the restore branch. **Fix:** also set it when there is no draft. `dispose` flushes a pending debounce instead of cancelling it. **What to watch:** any early return or throw in `_loadDraft` (for example, `byName` on a renamed enum in an old draft) leaves autosave off.
**Where:** `lib/features/field_verification/field_verification_screen.dart:97-122`

### Nameplate OCR took "Number" as the serial (pre-2026-09-25)
**Cause:** overlapping labels were tried shortest-first, so "SERIAL" matched inside "Serial Number". **Fix:** try labels longest-first and stop after the first match. A test pins it. **What to watch:** adding short labels like "NO".
**Where:** `lib/core/ocr/nameplate_ocr.dart:58-78`, `test/nameplate_ocr_test.dart:62`

---

## Flutter, UI and i18n

### Never `push` a bottom-nav branch route (2026-09-07)
**What happened:** The app crashed with `!keyReservation.contains(key)`. **Cause:** pushing a `StatefulShellRoute` branch path onto the root navigator reserves that branch's navigator key a second time. **Fix:** switch branches (`dashboard`, `overview`, `orders`, `invites`, `profile`) with `context.go`. `Routes.isShellBranch()` exists for this check. **What to watch:** notification or deep-link handlers that `push` a route they got from the server.
**Where:** `lib/app/router.dart:108-121`

### The language reverted to English after switching tabs (2026-09-09)
**What happened:** Arabic reverted to English after moving between bottom-nav tabs. **Cause:** screens read `FlutterLocalization.instance.currentLocale` directly. The package's delegate freezes its string table at construction, and the shell's indexed-stack rebuilds let it drift from `currentLocale`. **Fix:** `LocaleController` is the only caller of `translate()`, and every widget watches it. `Directionality` is pinned explicitly in `app.dart`. **What to watch:** never read or set the locale through the package singleton.
**Where:** `lib/state/locale_controller.dart:6-62`, `lib/app/app.dart:73`

### An i18n key can be missing from both files at once (2026-09-25, open)
**What happened:** `common.pull_down_to_retry` is used in three screens but exists in neither `en.json` nor `ar.json`. **Cause:** only en and ar were compared with each other (both have 595 keys and match). **Fix:** not fixed. Add the key, plus a test that checks every `'x.y'.getString` literal in `lib/` against `en.json`. **What to watch:** key-parity checks alone can't catch this.
**Where:** `lib/features/profile/profile_screen.dart:130`, `lib/features/invites/invites_screen.dart:101`, `lib/features/notifications/notifications_screen.dart:88`

### Device-specific Flutter traps (pre-2026-09-25)
- **`PopupMenuButton` pops the whole screen on OPPO Android 16:** the system injects `KEYCODE_BACK` when the menu opens. Use an `IconButton` plus a confirm dialog instead (`lib/features/routes/route_list_screen.dart:429-433`).
- **A horizontal `ListView` inside a `Row` paints nothing, with no error dialog:** it gets unbounded width. Wrap it in `Expanded` plus a fixed-height `SizedBox` (`lib/features/scanner/scanner_screen.dart:903-907`).
- **`InteractiveViewer` defaults make large floor plans unreachable:** use `constrained: false` at native size, fit on the first frame, and draw the pin as a screen-space overlay (`lib/features/floor_plan/floor_plan_screen.dart:217-284`).
- **A proxy 502/504 HTML page must not become the error text:** `mapDioException` drops markup bodies (`lib/core/network/api_exception.dart:83-89`).

---

## Platform, build and release

### The committed default API host is a developer's LAN IP (2026-09-21 → 2026-09-25, open)
**What happened:** `env.dart`'s default moved from the dev host to `http://192.168.0.x:5002` and changed four times in five days (`a776fd3`, `8abd825`, `cacb3d1`, `0623005`). **Cause:** the default was edited instead of passing `--dart-define`. **What to watch:** a plain `flutter build appbundle` ships a private-IP `http` host, and cleartext is allowed app-wide (`AndroidManifest.xml:22`). Always pass `API_BASE_URL` **and** `WEB_BASE_URL` (no `/api` suffix). The login screen's server override changes only the API host and applies after a restart; it is also visible in release builds.
**Where:** `lib/app/env.dart:4-19`, `lib/features/login/login_screen.dart:449-460`

### A release build without a keystore silently signs with the debug key (pre-2026-09-25)
**What happened:** With no `android/key.properties`, `bundleRelease` still succeeds, signed with the debug key. The macOS checkout has neither `key.properties` nor the `.jks`, which live on the Windows machine. **What to watch:** always run `jarsigner -verify` on the AAB. Bump the `+BUILD` part of `pubspec.yaml` on every Play upload and record it in `VERSIONING.md`, which currently stops at build 2 while pubspec is at `+3`. New Firebase SHA fingerprints are needed per keystore, or FCM fails on release builds.
**Where:** `android/app/build.gradle.kts:60-66`, [VERSIONING.md](VERSIONING.md), [RELEASE_INFO.md](RELEASE_INFO.md)

### Windows-only Gradle workarounds came along to macOS (pre-2026-09-25)
**What happened:** Every Android subproject is pinned to NDK `30.0.16138531`, with `kotlin.incremental=false` and an 8 GB heap. `build.gradle.kts.bak` is the file from before the pin. **Cause:** the Windows machine had a partial newer NDK download and failing Kotlin cache closes. **What to watch:** the first Mac Android build needs that NDK installed (only 26.x is present) or the pin re-evaluated.
**Where:** `android/build.gradle.kts:18-28`, `android/gradle.properties`

### This Mac can't run the toolchain yet (2026-09-25)
**What happened:** `flutter pub get` fails the SDK constraint. **Cause:** the zsh `flutter` alias points to a path that doesn't exist (`~/.zshrc:131-132`), and `~/.zshrc:6` has a PATH entry missing its leading `/`. The newest SDK installed is 3.19.3, while `pubspec.lock` needs Flutter ≥ 3.44.0 / Dart ≥ 3.13.2. **What to watch:** any "analyze clean / tests pass" claim made from this Mac right now is unverified. Install Flutter 3.44+ first.

---

## AR BIM overlay (planned, not built)

Full plan: [docs/ar-bim-overlay.md](docs/ar-bim-overlay.md). These are the findings from the 2026-09-25 design pass that would otherwise have to be rediscovered.

### `bim_elements` carries no geometry, so the server has no mesh to send (2026-09-25)
**What happened:** the AR plan assumed the existing IFC pipeline could feed an overlay. It can't. `ifcExtractor.ts` imports `web-ifc` but uses only its attribute APIs — `bim_elements` stores property sets, containment and classifications, and `hadRepresentation` is a **boolean**, not a mesh. `building_3d_models.fileUrl` points at the raw IFC, not at anything a phone can draw. **What to watch:** any "we already have the model" claim about BIM features. Tessellation, glTF authoring, chunking and a `nodeIndex → globalId` map are all new work (AR-5 … AR-8). The identity model is the part that already exists.
**Where:** `../fusion-eco-server/src/services/bim/ifcExtractor.ts:1`, `../fusion-eco-server/src/model/bim-element.ts:19`

### The two obvious ARCore features are both the wrong tool here (2026-09-25)
**What happened:** ARCore offers Cloud Anchors (persistent shared alignment) and Augmented Images (marker tracking). Both look like the answer and both were rejected. **Cause:** Cloud Anchors needs a Google Cloud project and **a network round trip to resolve** — FieldOps exists because plant rooms have no signal, so a hosted anchor service is an architectural contradiction, not just a quota question. Augmented Images wants feature-rich, non-repeating artwork and scores QR codes poorly; it also needs a pre-built image database, so adding a marker on site would need an app release. **The fix:** take the four corner points the platform barcode detector already returns (ML Kit on Android, Vision on iOS), and solve the planar pose in our own Dart. One code path, any marker, no database, no network.
**Where:** [docs/ar-bim-overlay.md §2.2, §4.2](docs/ar-bim-overlay.md)

### Only four degrees of freedom are unknown, and two of them must be thrown away (2026-09-25)
**What happened:** the BIM→world transform looks like a 6-DoF problem and is really 4-DoF: ARCore/ARKit build a gravity-aligned world frame and IFC is Z-up, so the accelerometer supplies pitch and roll. That is why a single marker suffices. **What to watch:** a planar PnP solve returns all six, and its pitch/roll are the noisy components at oblique viewing angles. Keep the yaw, take pitch and roll from gravity, re-orthonormalise. Skipping that step is the difference between an overlay that sits still and one that visibly swims. Yaw error is also the dominant accuracy term because it pivots the model about the marker — 1° is 17 mm at 1 m but 350 mm at 20 m, which is why the design wants many markers rather than one good one.
**Where:** [docs/ar-bim-overlay.md §3.1, §4.2, §5](docs/ar-bim-overlay.md)

### Re-centring the model on export silently breaks every stored coordinate (2026-09-25)
**What happened:** real models sit at site eastings/northings in the hundreds of thousands, which destroys float32 precision in a renderer, so exporters re-centre near the origin. **What to watch:** if marker poses, element centroids or camera poses are not shifted by that **same** offset, the overlay lands kilometres away and it looks like an AR tracking bug. Rule adopted: resolve `IfcMapConversion`/`IfcSite` once at export, write the offset to `building_3d_models.metadata`, and serve everything in that re-centred frame thereafter. One conversion, one place.
**Where:** [docs/ar-bim-overlay.md §3.3](docs/ar-bim-overlay.md), `../fusion-eco-server/src/model/building-3d-model.ts:10`

### AR packs make two open queue/cache bugs load-bearing (2026-09-25)
**What happened:** the AR pack is a route pack with geometry in it, so it inherits `route_download_service`'s behaviour — including improvements.md **#14**, where `If-None-Match` is never sent and a download REPLACEs rather than merges. At route-pack size that is wasteful; at 60 MB a storey it is unusable. Likewise **#1**, where logout (any 401) wipes the queue: an AR finding is the most expensive capture to lose, because reproducing it means walking back to the spot. **What to watch:** fix #14 before AR-14 ships and #1 before AR-19 ships. Also: GLB chunks go on disk referenced by path, never base64 in a SQLite row — that habit already costs the Sync Center an O(n²) decode (#12).
**Where:** [docs/improvements.md](docs/improvements.md) #1, #12, #14; [docs/ar-bim-overlay.md §8](docs/ar-bim-overlay.md)

### v2 revision: yaw comes from marker *positions*, not marker orientation (2026-09-25, supersedes part of an entry above)
**What happened:** v1 of the AR plan (and the entry above, "Only four degrees of freedom are unknown…") took yaw from each marker's own orientation, and replaced the transform whenever a new marker was scanned. On review, that orientation is the noisiest quantity measured: about 0.5–2° from a 200 mm target, which is 175–700 mm at 20 m. **Fix adopted in v2:** keep every marker seen in the tracking session as a native anchor, and fit yaw and translation by closed-form 4-DoF weighted least squares on their **positions**. Error falls roughly as `σ_p / (r_rms·√n)`: two markers 5 m apart give about 0.16°, and four around a room about 0.05°. A single marker's yaw comes from the tracked wall-plane normal, and PnP is used only as a down-weighted fallback. **What to watch:** "re-anchor to the nearest marker" throws information away, so combine observations instead. Residuals then give *measured* quality and catch a moved marker automatically. The gravity point in the entry above still holds.
**Where:** [docs/ar-bim-overlay.md §4.3–4.4](docs/ar-bim-overlay.md)

### The web twin FieldOps embeds runs on AGPL-3.0 code (2026-09-25, open)
**What happened:** checking whether AR could reuse the web twin's geometry turned up `@xeokit/xeokit-sdk` 2.6.109 (package licence **AGPL-3.0**) in at least 11 client components, and `@xeokit/xeokit-convert` (AGPL-3.0 LICENSE file) run by `app/api/digital-twin/convert-ifc/route.ts`. The technician twin page that `twin_screen.dart:57` opens in a WebView is one of those components. **What to watch:** it conflicts with the no-licence requirement unless a commercial xeokit licence is held. That is a licensing-owner decision (Track W, W-1), not an engineering fix. Until it's decided, never build new features on XKT or `convert2xkt`. AR builds from source IFC with web-ifc (MPL-2.0), so models that exist **only** as `.xkt` can't be used in AR until someone uploads their IFC.
**Where:** `../fusion-eco-client/package.json`, `../fusion-eco-client/components/digital-twin/TwinLiteViewer.tsx`, [docs/ar-bim-overlay.md §2.3](docs/ar-bim-overlay.md)

### The app has no IFC GlobalId, and the server's asset ↔ element join has a confidence (2026-09-25)
**What happened:** v1 assumed tap-to-identify and "show this asset" could rely on the element ↔ asset join as fact. Nothing in `lib/` mentions a GlobalId, and route-pack assets don't carry one (`route_pack.dart:41`). On the server the join is `assets.ifcGlobalId` plus `asset_mappings` with `confidence` and `method: auto | human | imported`. **What to watch:** highlighting a low-confidence automatic match as *the* asset sends a technician to the wrong valve. Show confidence, list candidates, and turn an aligned field identification into a human confirmation. Any feature that needs the join on the device first needs an additive field on route-pack assets (AR-12).
**Where:** `../fusion-eco-server/src/model/asset.ts:105`, `../fusion-eco-server/src/model/asset-mapping.ts:10`

### IFC → glTF needs an axis swap as well as a re-centre, and web-ifc already does the re-centre (2026-09-25)
**What happened:** v1 covered the far-from-origin re-centring but not the axis swap. IFC is Z-up; glTF and ARCore/ARKit are Y-up. `(x, y, z) → (x, z, −y)` must happen exactly once, at export. The installed web-ifc 0.0.77 already has `COORDINATE_TO_ORIGIN` and `GetCoordinationMatrix()`, so the re-centring offset comes from the library rather than hand-written maths. `ifcExtractor.ts:186` calls `OpenModel` with default settings (attributes only), so the geometry build must open the model with its own settings. **What to watch:** keep one golden-vector JSON that both the TypeScript and Dart tests assert, so the server and the app can't disagree about frames without a test failing.
**Where:** [docs/ar-bim-overlay.md §3](docs/ar-bim-overlay.md), `../fusion-eco-server/src/services/bim/ifcExtractor.ts:186`

### One scene node per BIM element doesn't scale on a phone (2026-09-25)
**What happened:** v1 planned a `nodeIndex → globalId` map with one node per element. A single storey can hold tens of thousands of elements, which means tens of thousands of draw calls, against about 100–200 a mobile GPU manages. **Fix adopted:** spatial tiles merged by material, a per-vertex `_FEATURE_ID_0` (EXT_mesh_features), and a feature-state texture for highlight and visibility, so identity survives the merge and a highlight costs one texture upload. Architecture is drawn as edges only, which also works as a live alignment check. Whether Filament reads the custom attribute and extensions in this setup is unverified until AR-2, and §5.4 lists the fallback.
**Where:** [docs/ar-bim-overlay.md §5.3–5.4](docs/ar-bim-overlay.md)

### xeokit decision: remove it, open source only (2026-09-25)
**Decision:** the user ruled out a commercial xeokit licence. The web twin moves to three.js (MIT) on the shared glTF tiles (Track W, W-1…W-4 in [docs/ar-bim-overlay.md §11](docs/ar-bim-overlay.md)). This settles the open question in the entry "The web twin FieldOps embeds runs on AGPL-3.0 code" above. **What to watch:** only permissive licences (MIT, Apache-2.0, BSD; MPL-2.0 for web-ifc). Add a CI licence scan so no AGPL or GPL package comes back in through a transitive dependency.

### Filament's glTF loader doesn't read EXT_mesh_features or EXT_mesh_gpu_instancing (2026-09-25)
**What happened:** v2 of the AR plan put per-vertex feature IDs in `_FEATURE_ID_0` (EXT_mesh_features) and relied on EXT_mesh_gpu_instancing. Checked against the Filament README: gltfio supports KHR_mesh_quantization and EXT_meshopt_compression (plus Draco and the KHR material extensions), and **neither of those two**. **Fix adopted in v3:** a tile-local feature index in `TEXCOORD_1` (an unsigned 16-bit integer through KHR_mesh_quantization, excluded from gltf-transform's quantize step so it stays exact) plus a per-tile index → `featureId` table. Repeated geometry is expanded at export, with Filament's `InstanceBuffer` API as the later option. **What to watch:** before choosing any glTF extension for the tiles, check it against Filament's supported list, and remember three.js must read the same file for the web twin.
**Where:** [docs/ar-bim-overlay.md §5.4](docs/ar-bim-overlay.md)

### iPad support rules out WebXR; AR is native, with Filament on both platforms (2026-09-25, decision)
**What happened:** the user made iPhone and iPad first-class targets for a product with no licences. Researched in September 2026: Chrome on Android has full WebXR AR (hit-test, anchors, depth, DOM overlay, raw camera access since Chrome 107), but **Safari on iPhone and iPad has no `immersive-ar`** and no public timeline, and **Android WebView has no WebXR** either, so a web page can't do AR inside FieldOps. RealityKit loads **only USDZ, not glTF** (GLTFKit2, MIT, converts), so it would need a second material and a second tile path. **Decision:** ARCore and ARKit for tracking, **Filament for rendering on both** (Android through SceneView, which is actively released; Sceneform was archived in March 2026; iOS follows Google's official `ios/samples/hello-ar`). RealityKit + GLTFKit2 is the iOS fallback if AR-37 fails. **What to watch:** FieldOps doesn't launch on iOS yet (Track I). LiDAR iPads get the best hit-tests on plain walls.
**Where:** [docs/ar-bim-overlay.md §0, §2.4, §11](docs/ar-bim-overlay.md)
