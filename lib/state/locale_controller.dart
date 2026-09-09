import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/locale_config.dart';

/// The single source of truth for the app's active language.
///
/// Bug history (fixed 2026-09-09): the EN/AR switcher used to call
/// `FlutterLocalization.instance.translate(...)` directly, and every screen
/// — including `MaterialApp.router`'s own `locale:` param in app/app.dart —
/// read the current language straight back off that package's singleton
/// (`FlutterLocalization.instance.currentLocale`) inside `build()`, relying
/// on one global callback (`onTranslatedLanguage`) to call `setState()` on
/// the one widget listening for it. That worked for the switch itself, but
/// nothing kept the package's internal delegate
/// (`FlutterLocalizationDelegate`, which freezes the locale it will load
/// into its string table at *construction* time rather than re-reading it
/// from `Localizations` on every resolve — see that class's `load()`)
/// synchronized with what the rest of the app displayed once *anything
/// else* caused a rebuild — such as go_router's
/// `StatefulShellRoute.indexedStack` switching bottom-nav branches, a class
/// of locale/router interaction with documented upstream quirks
/// (flutter/flutter#138396, "the whole app restart when locale changed").
/// Symptom: the language visibly reverted to English after navigating
/// between tabs and back, with nothing in the app having asked for English
/// again — the shared, single, mutable string table the package keeps
/// (`FlutterLocalizationTranslator.instance._string`) had simply drifted out
/// of sync with what `currentLocale` still (correctly) reported.
///
/// Routing every read AND every write of the active language through this
/// one [Notifier] closes that gap structurally: it is the *only* thing in
/// the app that ever calls [FlutterLocalization.translate], so the
/// package's delegate and this provider's `state` always change atomically
/// in the same call — there's no window left where they can disagree — and
/// every widget that needs the active language `ref.watch`s this instead of
/// reaching into the package's mutable singleton directly, so they all
/// update together, deterministically, on every rebuild rather than only
/// when the one legacy callback happened to have fired.
class LocaleController extends Notifier<String> {
  @override
  String build() {
    // `ensureInitialized()` (called in main() before runApp) already
    // restored any previously-saved language choice into `currentLocale`.
    // Only "en"/"ar" are wired up right now, so anything else (a fresh
    // install picking up the device locale, or a stale value) falls back to
    // English — the app's documented default.
    final restored = FlutterLocalization.instance.currentLocale?.languageCode;
    return restored == AppLocales.arabic
        ? AppLocales.arabic
        : AppLocales.english;
  }

  /// Flips the active language. [FlutterLocalization.translate] keeps the
  /// package's delegate (and its own SharedPreferences persistence)
  /// working; updating [state] in the very same call is what every screen
  /// that watches this provider actually reacts to.
  void set(String languageCode) {
    if (languageCode == state) return;
    FlutterLocalization.instance.translate(languageCode);
    state = languageCode;
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, String>(
  LocaleController.new,
);
