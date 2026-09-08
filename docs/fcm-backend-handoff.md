# FCM push — backend work needed

The Flutter technician app now registers its FCM (Firebase Cloud Messaging) device
token with the server on login/resume, and expects the server to push through Firebase
alongside the existing socket.io notification. This is net-new work — no push path
exists today (see `docs/analysis/03-server-api-contract.md:663-667`).

Firebase project: `fusion-eco-technician`. Service account key (JSON) is being added
manually — see step 4.

## 1. New table `device_tokens`

Columns: `id` (uuid, pk), `userId` (fk → users), `token` (string, unique), `platform`
(enum: `android` | `ios`), `createdAt`, `updatedAt`.

One user can have multiple rows (multiple devices). `token` must be unique — upsert
on conflict (a token can move between users if a phone is re-logged-in as someone
else).

## 2. Two new routes, under the existing `notificationRoutes.ts` (already behind
   `router.use(decodeToken)` at `:8`, so auth is automatic — take `userId` from
   `req.user.id`, never from the body)

```
POST /api/notifications/register-device
  body: { token: string, platform: "android" | "ios" }
  → upsert device_tokens row keyed on token, set/overwrite userId
  → 200 { success: true }

POST /api/notifications/unregister-device
  body: { token: string }
  → delete device_tokens row matching token (ownerless if not found — no error)
  → 200 { success: true }
```

## 3. Hook the actual send into `notificationService.ts`

Inside `createNotification` (`src/services/notificationService.ts`), right next to the
existing `emitToUser` socket call (`:36`, `:91-95`) — add an FCM send using
`firebase-admin`'s Admin SDK:

- Look up all `device_tokens` rows for the notification's `userId`.
- Send via `admin.messaging().sendEachForMulticast(...)` — data payload should carry
  the same fields the client already knows how to route on
  (`lib/core/push/push_service.dart` / `lib/core/utils/notification_route.dart`):
  `title`, `link`, `entityId`, `entityType`. Keep it a **data-only** message (no
  `notification` block) so the client controls foreground display instead of the OS
  auto-showing a default banner.
- On a response entry with error code `messaging/registration-token-not-registered`
  or `messaging/invalid-registration-token`, delete that `device_tokens` row —
  the device uninstalled or the token rotated without ever calling
  register-device again.

## 4. Service account key

`firebase-admin` needs a service account JSON to call the Admin SDK. **Do not commit
it.** Put it wherever other secrets already live for this service (env var holding
the JSON, or a mounted secret file path via env var) and init once at boot:

```ts
import admin from "firebase-admin";
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON!)),
});
```

I already downloaded the key from Firebase console (Project Settings → Service
Accounts → Generate new private key) — adding it to the backend env manually, not
through this repo.

## 5. iOS note (not blocking Android)

iOS push additionally needs an APNs (Apple Push Notification service) auth key
uploaded into the *Firebase console* (Project Settings → Cloud Messaging → Apple app
config) — that's a Firebase-side config, not backend code. Nothing here changes for
iOS once that's uploaded; same `sendEachForMulticast` call covers both platforms.

## Client contract already live (Android)

`technician_portal` already calls `register-device` on login and app-resume, and
`unregister-device` on logout (best-effort, non-blocking). Until routes 1–3 above
exist server-side, those calls just fail silently (caught client-side) — no client
changes needed once the backend routes land.
