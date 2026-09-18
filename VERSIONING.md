# Versioning Policy

Format in `pubspec.yaml`: `version: MAJOR.MINOR.PATCH+BUILD`

- `MAJOR.MINOR.PATCH` — semver, human-facing (shown to users, App/Play listing "version").
  - MAJOR: breaking/incompatible change (rare for this app).
  - MINOR: new feature.
  - PATCH: bugfix / config-only change (e.g. pkg name, endpoint).
- `BUILD` — Play Console `versionCode`. Must strictly increase on **every** upload, forever, even across MAJOR/MINOR/PATCH bumps or reverts. Never reuse, never decrease.

Rule: before every Play Console upload, bump `BUILD` by at least 1. Bump `MAJOR.MINOR.PATCH` per semver rule above. `flutter build appbundle` reads both straight from `pubspec.yaml` — nothing else to touch.

Track last-shipped BUILD number here so it survives even if Play Console access changes:

| Build | Version name | Package | Date | Note |
|---|---|---|---|---|
| 1 | 1.0.0 | com.thefusionapps.fusioneco.technician | 2026-09-15 | first upload attempt, rejected — pkg name wrong per TL |
| 2 | 1.0.1 | com.fusionapps.fieldops | 2026-09-18 | pkg renamed to com.fusionapps.fieldops per TL request |
