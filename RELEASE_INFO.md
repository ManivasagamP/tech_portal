# Technician App — Release Build Info

Built: 2026-09-15. Copy into Notion yourself.

## Output
- AAB: `D:\fe_portals\technician_portal\build\app\outputs\bundle\release\app-release.aab` (78.6MB)
- Version: 1.0.0+1 (from pubspec.yaml)
- Package: com.thefusionapps.fusioneco.technician
- Signed with: release key (CN=Fusion Eco), NOT debug — verified via jarsigner.

## Signing key (SECRET — do not put in Notion)
- Keystore file: `D:\fe_portals\technician_portal\android\fusion-eco-technician.jks`
- Passwords/alias: `D:\fe_portals\technician_portal\android\key.properties` (gitignored, both files stay local)
- Back this .jks up somewhere safe NOW (password manager vault, encrypted drive). Lose it = can never publish an update to this Play Store listing again under the same app.

## Build config used (env.dart dart-define, dev defaults — not overridden)
- API_BASE_URL: `http://api.test.develop.thefusionapps.com`
- WEB_BASE_URL: `http://10.0.2.2:3000`
- BRAND_NAME: `Fusion Eco`
- connectTimeout: 15s / receiveTimeout: 30s / uploadTimeout: 120s
- cacheTtl: 24h / maxMutationAttempts: 5 / prefetchThrottle: 4h

⚠️ These are dev-environment values. Confirm this is intentional before submitting to Play Store — a prod release usually should point at prod API_BASE_URL/WEB_BASE_URL, not the `.test.develop.` host.

## Firebase (google-services.json)
- Project ID: fusion-eco-technician
- Project number: 552357954709
- App ID: 1:552357954709:android:abb02bdc8887bceb5d879c
- API key: AIzaSyCYiY5d6Qbbgs0kU70NQQFxEuRuXbNSxys
  (this key is restricted by Firebase to this Android package+SHA, not a bearer secret — safe to share in Notion)
