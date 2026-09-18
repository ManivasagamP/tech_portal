# Technician App — Release Build Info

Built: 2026-09-18. Copy into Notion yourself.

## Output
- AAB: `D:\fe_portals\technician_portal\build\app\outputs\bundle\release\app-release.aab` (78.6MB)
- Version: 1.0.1+2 (from pubspec.yaml) — see [VERSIONING.md](VERSIONING.md) for the bump policy
- Package: com.fusionapps.fieldops (changed from com.thefusionapps.fusioneco.technician per TL request — new Play Console app listing, package can't be changed once set there)
- Signed with: release key (CN=Fusion Eco), NOT debug — verified via jarsigner.

## Signing key (SECRET — do not put in Notion)
- Keystore file: `D:\fe_portals\technician_portal\android\fusion-eco-technician.jks`
- Passwords/alias: `D:\fe_portals\technician_portal\android\key.properties` (gitignored, both files stay local)
- Back this .jks up somewhere safe NOW (password manager vault, encrypted drive). Lose it = can never publish an update to this Play Store listing again under the same app.

## Build config used (env.dart dart-define, defaults — not overridden)
- API_BASE_URL: `https://dev.api.eco.thefusionapps.com`
- WEB_BASE_URL: `https://dev.eco.thefusionapps.com`
- BRAND_NAME: `Fusion Eco`
- connectTimeout: 15s / receiveTimeout: 30s / uploadTimeout: 120s
- cacheTtl: 24h / maxMutationAttempts: 5 / prefetchThrottle: 4h

⚠️ Still a `dev.` host, not confirmed prod. Verified working end-to-end on device (login + FCM push) against this host. Confirm before Play Store submission whether this should point at a prod domain instead.

## FCM push — verified working
Tested 2026-09-18 on physical device (CPH2667), logged in as balaji@eco.com, self-triggered a real event — push arrived. Confirms package rename + new google-services.json + SHA fingerprints are all correctly wired.

## Firebase (google-services.json)
- Project ID: fusion-eco-technician
- Project number: 552357954709
- App ID (new, com.fusionapps.fieldops): 1:552357954709:android:628d4c26708a49a55d879c
- App ID (old, com.thefusionapps.fusioneco.technician — kept, unused): 1:552357954709:android:abb02bdc8887bceb5d879c
- API key: AIzaSyCYiY5d6Qbbgs0kU70NQQFxEuRuXbNSxys
  (this key is restricted by Firebase to Android package+SHA, not a bearer secret — safe to share in Notion)
- ⚠️ Release keystore SHA-1/SHA-256 fingerprints still need adding to the new Firebase app entry (Project settings → Your apps → com.fusionapps.fieldops → Add fingerprint), or FCM push notifications won't authenticate on release builds. Get them with:
  `keytool -list -v -keystore android\fusion-eco-technician.jks -alias <alias-from-key.properties>`
