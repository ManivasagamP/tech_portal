import 'package:flutter/widgets.dart';
import 'package:flutter_localization/flutter_localization.dart';

/// Central registry of the app's supported languages.
///
/// To add a third language later:
/// 1. Drop `assets/i18n/<code>.json` in with the same keys as `en.json`.
/// 2. Add one [JsonLocale] entry to [AppLocales.supported] below.
/// That's it — `pubspec.yaml` already declares the whole `assets/i18n/`
/// folder, and [AppLocales.languageNames] only needs a label for the
/// switcher UI.
abstract final class AppLocales {
  static const english = 'en';
  static const arabic = 'ar';

  /// Languages that read right-to-left. Anything not listed here is
  /// treated as LTR.
  static const rtlLanguageCodes = <String>{arabic};

  static const supported = <JsonLocale>[
    JsonLocale(english, 'assets/i18n/en.json'),
    JsonLocale(arabic, 'assets/i18n/ar.json'),
  ];

  /// Display names for the language switcher, keyed by language code.
  static const languageNames = <String, String>{
    english: 'English',
    arabic: 'العربية',
  };

  static bool isRtl(String? languageCode) =>
      languageCode != null && rtlLanguageCodes.contains(languageCode);

  /// Builds the [Locale] MaterialApp should use for a given language code —
  /// matching [JsonLocale.locale]'s shape (no country/script subtags for
  /// either supported language) so it's guaranteed to exactly match an entry
  /// in [supported], which is what lets Flutter use it verbatim instead of
  /// falling back to locale-resolution against the device's locale.
  static Locale localeFor(String languageCode) => Locale(languageCode);
}
