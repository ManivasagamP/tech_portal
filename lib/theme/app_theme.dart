import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'theme_extensions.dart';

/// Light-only, matching the web technician portal. It ships no dark variants.
abstract final class AppTheme {
  static ThemeData build() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.orange600,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.orange50,
      onPrimaryContainer: AppColors.orange700,
      secondary: AppColors.ink,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.gray100,
      onSecondaryContainer: AppColors.gray900,
      tertiary: AppColors.purple600,
      onTertiary: AppColors.white,
      error: AppColors.red600,
      onError: AppColors.white,
      errorContainer: AppColors.red50,
      onErrorContainer: AppColors.red700,
      surface: AppColors.white,
      onSurface: AppColors.gray900,
      onSurfaceVariant: AppColors.gray500,
      surfaceContainerLowest: AppColors.white,
      surfaceContainerLow: AppColors.gray50,
      surfaceContainer: AppColors.gray100,
      outline: AppColors.gray200,
      outlineVariant: AppColors.gray100,
      scrim: Color(0x80000000),
      shadow: Color(0x0D000000),
      inverseSurface: AppColors.slate800,
      onInverseSurface: AppColors.white,
    );

    final text = _textTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.gray50,
      canvasColor: AppColors.white,
      splashFactory: InkRipple.splashFactory,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 53,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(color: AppColors.white),
        shape: const Border(bottom: BorderSide(color: AppColors.inkBorder)),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange600,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.orange600.withValues(alpha: 0.5),
          disabledForegroundColor: AppColors.white.withValues(alpha: 0.8),
          elevation: 0,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
          animationDuration: const Duration(milliseconds: 120),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.gray700,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          side: const BorderSide(color: AppColors.gray300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
          animationDuration: const Duration(milliseconds: 120),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange600,
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        constraints: const BoxConstraints(minHeight: 40),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.gray400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gray200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gray200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.orange600, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red600),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red600, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: AppColors.gray600),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.gray200,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.orange600,
        linearTrackColor: AppColors.gray100,
        linearMinHeight: 12,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.gray300, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.orange600
              : Colors.transparent,
        ),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        FeStatusColors(),
        FeElevation(),
        FeSpacing(),
        FeRadii(),
        FeMetrics(),
        FeMotion(),
        FeOrderTypeColors(),
        FeAccents(),
      ],
    );
  }

  static TextTheme _textTheme() {
    const onSurface = AppColors.gray900;
    final base = TextTheme(
      displaySmall: const TextStyle(
        fontSize: 36,
        height: 40 / 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
        color: onSurface,
      ),
      headlineMedium: const TextStyle(
        fontSize: 30,
        height: 36 / 30,
        fontWeight: FontWeight.w900,
        color: onSurface,
      ),
      headlineSmall: const TextStyle(
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleMedium: const TextStyle(
        fontSize: 18,
        height: 28 / 18,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleSmall: const TextStyle(
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      bodyLarge: const TextStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: AppColors.gray600,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: AppColors.gray500,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.gray400,
      ),
      labelSmall: const TextStyle(
        fontSize: 10,
        height: 14 / 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AppColors.gray500,
      ),
    );
    return GoogleFonts.interTextTheme(base);
  }
}

/// Overrides for the screens that paint a **white** app bar instead of the
/// themed dark one — the order detail, the twin, the in-app browser and the
/// scanner.
///
/// Setting `backgroundColor` alone is not enough, and fails invisibly. The
/// theme's app bar is dark ink with white content, so a screen that repaints
/// the bar white must recolour everything on it:
///
/// * `foregroundColor` handles the icons.
/// * The **title** needs its own style. `AppBarTheme.titleTextStyle` is set
///   explicitly (and white), and an explicit title style wins over
///   `foregroundColor` — so the title alone would stay white on white.
/// * `systemOverlayStyle` has to flip too, or the status bar keeps drawing
///   light icons above a white bar and the clock disappears with them.
abstract final class FeLightAppBar {
  static const foreground = AppColors.gray900;
  static const overlay = SystemUiOverlayStyle.dark;

  static TextStyle? title(BuildContext context) =>
      Theme.of(context).appBarTheme.titleTextStyle
          ?.copyWith(color: AppColors.gray900);
}
