import 'package:flutter/material.dart';

import '../domain/maintenance_record.dart' show OrderType;
import 'app_colors.dart';

@immutable
class FeChipStyle {
  const FeChipStyle({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

/// Chip palettes lifted verbatim from `components/technician/OrderCard.tsx` and the
/// order-detail pages. The web app deliberately runs two different priority palettes
/// (cards paint Medium blue, detail pages paint it yellow); both are kept.
@immutable
class FeStatusColors extends ThemeExtension<FeStatusColors> {
  const FeStatusColors();

  static const _completed = FeChipStyle(
    background: AppColors.green100,
    foreground: AppColors.green700,
    border: AppColors.green200,
  );
  static const _inProgress = FeChipStyle(
    background: AppColors.blue100,
    foreground: AppColors.blue700,
    border: AppColors.blue200,
  );
  static const _onHold = FeChipStyle(
    background: AppColors.yellow100,
    foreground: AppColors.yellow700,
    border: AppColors.yellow200,
  );
  static const _cancelled = FeChipStyle(
    background: AppColors.gray100,
    foreground: AppColors.gray700,
    border: AppColors.gray200,
  );
  static const _statusFallback = FeChipStyle(
    background: AppColors.slate100,
    foreground: AppColors.slate700,
    border: AppColors.slate200,
  );

  /// Substring matching, same order as the web switch — "pending" lands on the
  /// on-hold palette, which is intentional there.
  FeChipStyle status(String? value) {
    final v = (value ?? '').toLowerCase();
    if (v.contains('completed') || v.contains('closed')) return _completed;
    if (v.contains('progress')) return _inProgress;
    if (v.contains('hold') || v.contains('pending')) return _onHold;
    if (v.contains('cancel')) return _cancelled;
    return _statusFallback;
  }

  /// OrderCard palette — Medium is blue here.
  FeChipStyle priorityOnCard(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'critical':
        return const FeChipStyle(
          background: AppColors.red50,
          foreground: AppColors.red600,
          border: AppColors.red100,
        );
      case 'high':
        return const FeChipStyle(
          background: AppColors.orange50,
          foreground: AppColors.orange600,
          border: AppColors.orange100,
        );
      case 'medium':
        return const FeChipStyle(
          background: AppColors.blue50,
          foreground: AppColors.blue600,
          border: AppColors.blue100,
        );
      case 'low':
        return const FeChipStyle(
          background: AppColors.green50,
          foreground: AppColors.green600,
          border: AppColors.green100,
        );
      default:
        return const FeChipStyle(
          background: AppColors.gray50,
          foreground: AppColors.gray600,
          border: AppColors.gray100,
        );
    }
  }

  /// Order-detail pill palette — Medium is yellow here.
  FeChipStyle priorityOnDetail(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'critical':
        return const FeChipStyle(
          background: AppColors.red100,
          foreground: AppColors.red700,
          border: AppColors.red100,
        );
      case 'high':
        return const FeChipStyle(
          background: AppColors.orange100,
          foreground: AppColors.orange700,
          border: AppColors.orange100,
        );
      case 'medium':
        return const FeChipStyle(
          background: AppColors.yellow100,
          foreground: AppColors.yellow700,
          border: AppColors.yellow100,
        );
      default:
        return const FeChipStyle(
          background: AppColors.green100,
          foreground: AppColors.green700,
          border: AppColors.green100,
        );
    }
  }

  @override
  FeStatusColors copyWith() => const FeStatusColors();

  @override
  FeStatusColors lerp(ThemeExtension<FeStatusColors>? other, double t) => this;
}

@immutable
class FeElevation extends ThemeExtension<FeElevation> {
  const FeElevation();

  static const sm = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const base = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 1),
      blurRadius: 2,
      spreadRadius: -1,
    ),
  ];
  static const md = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -1,
    ),
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: -2,
    ),
  ];
  static const lg = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 10),
      blurRadius: 15,
      spreadRadius: -3,
    ),
    BoxShadow(
      color: Color(0x1A000000),
      offset: Offset(0, 4),
      blurRadius: 6,
      spreadRadius: -4,
    ),
  ];
  static const xxl = <BoxShadow>[
    BoxShadow(
      color: Color(0x40000000),
      offset: Offset(0, 25),
      blurRadius: 50,
      spreadRadius: -12,
    ),
  ];
  static const navBar = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D000000),
      offset: Offset(0, -4),
      blurRadius: 6,
      spreadRadius: -1,
    ),
  ];

  /// The soft-card system's default: a wide, low-opacity, neutral shadow with
  /// no hard second layer — the "card floats a millimetre off the page" look
  /// the reference screens use everywhere, as opposed to [sm]'s thin 1px-ish
  /// definition line.
  static const soft = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F1F2937),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Color(0x08000000),
      offset: Offset(0, 2),
      blurRadius: 6,
      spreadRadius: -2,
    ),
  ];

  /// [soft] tinted by the card's own accent colour instead of neutral grey —
  /// used behind a stat card or badge so its shadow reads as "glowing its own
  /// colour" rather than sitting under generic grey haze. Pass the accent at
  /// low alpha (~0x22-0x33) as the shadow colour.
  static List<BoxShadow> tinted(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.18),
      offset: const Offset(0, 10),
      blurRadius: 24,
      spreadRadius: -8,
    ),
    const BoxShadow(
      color: Color(0x08000000),
      offset: Offset(0, 2),
      blurRadius: 6,
      spreadRadius: -2,
    ),
  ];

  /// Detached floating bars — the bottom nav and any FAB-like control that
  /// sits above the page rather than flush against an edge.
  static const floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A1F2937),
      offset: Offset(0, 12),
      blurRadius: 32,
      spreadRadius: -8,
    ),
  ];

  @override
  FeElevation copyWith() => const FeElevation();

  @override
  FeElevation lerp(ThemeExtension<FeElevation>? other, double t) => this;
}

@immutable
class FeSpacing extends ThemeExtension<FeSpacing> {
  const FeSpacing();

  final double xs = 4;
  final double sm = 8;
  final double md = 12;
  final double lg = 16;
  final double xl = 20;
  final double xxl = 24;
  final double xxxl = 32;

  final double pageGutter = 16;
  final double sectionGap = 16;
  final double listGap = 12;
  final double cardPad = 16;

  @override
  FeSpacing copyWith() => const FeSpacing();

  @override
  FeSpacing lerp(ThemeExtension<FeSpacing>? other, double t) => this;
}

@immutable
class FeRadii extends ThemeExtension<FeRadii> {
  const FeRadii();

  final double sm = 4;
  final double md = 6;
  final double lg = 8;
  final double card = 12;

  /// The soft-card system's default for anything that reads as a primary
  /// surface — dashboard/overview cards, order rows, the hero card. Bigger
  /// than [card] on purpose: the reference screens round everything closer
  /// to 20-24px, which is what makes flat rectangles read as soft "tiles"
  /// rather than boxes with rounded corners.
  final double xl = 20;
  final double sheet = 16;
  final double xxxl = 24;
  final double scanner = 32;

  @override
  FeRadii copyWith() => const FeRadii();

  @override
  FeRadii lerp(ThemeExtension<FeRadii>? other, double t) => this;
}

@immutable
class FeMetrics extends ThemeExtension<FeMetrics> {
  const FeMetrics();

  final double bottomNavHeight = 64;
  final double headerHeight = 53;
  final double listRow = 48;
  final double buttonSm = 36;
  final double buttonMd = 40;
  final double buttonLg = 44;
  final double buttonDialog = 48;
  final double buttonCta = 56;
  final double buttonScanner = 64;
  final double chartHeight = 256;

  @override
  FeMetrics copyWith() => const FeMetrics();

  @override
  FeMetrics lerp(ThemeExtension<FeMetrics>? other, double t) => this;
}

@immutable
class FeMotion extends ThemeExtension<FeMotion> {
  const FeMotion();

  final Duration fast = const Duration(milliseconds: 150);
  final Duration normal = const Duration(milliseconds: 200);
  final Duration sheetOpen = const Duration(milliseconds: 500);
  final Duration sheetClose = const Duration(milliseconds: 300);
  final Duration toastIn = const Duration(milliseconds: 350);
  final Duration toastLife = const Duration(milliseconds: 3000);
  final Duration progressFill = const Duration(milliseconds: 1000);
  final Duration scanLine = const Duration(milliseconds: 1500);

  /// Press feedback on a tappable card/chip — scale down then spring back.
  /// Kept under 200ms total so it never reads as lag (Quick Reference §7).
  final Duration press = const Duration(milliseconds: 120);

  /// Per-item delay in a staggered list entrance; multiplied by index and
  /// capped by [StaggeredEntrance] so a long list doesn't take seconds to
  /// finish revealing itself.
  final Duration staggerStep = const Duration(milliseconds: 45);
  final Duration entranceItem = const Duration(milliseconds: 380);

  final Curve standard = Curves.easeInOut;
  final Curve decelerate = Curves.easeOut;
  final Curve toastOvershoot = const Cubic(0.34, 1.3, 0.64, 1);

  /// A gentle overshoot-then-settle used for entrances and the progress
  /// ring — reads as "physical" rather than mechanical, without the harder
  /// bounce of [toastOvershoot].
  final Curve spring = const Cubic(0.16, 1, 0.3, 1);

  @override
  FeMotion copyWith() => const FeMotion();

  @override
  FeMotion lerp(ThemeExtension<FeMotion>? other, double t) => this;
}

@immutable
class FeOrderTypeColors extends ThemeExtension<FeOrderTypeColors> {
  const FeOrderTypeColors();

  final Color workOrder = AppColors.blue600;
  final Color preventive = AppColors.emerald600;
  final Color reactive = AppColors.red600;
  final Color annual = AppColors.amber600;

  /// Looks the four fields up by [OrderType] instead of the caller switching
  /// on it themselves everywhere a leading icon badge needs a colour.
  Color forType(OrderType type) => switch (type) {
    OrderType.workOrder => workOrder,
    OrderType.preventive => preventive,
    OrderType.reactive => reactive,
    OrderType.annual => annual,
  };

  @override
  FeOrderTypeColors copyWith() => const FeOrderTypeColors();

  @override
  FeOrderTypeColors lerp(ThemeExtension<FeOrderTypeColors>? other, double t) =>
      this;
}

/// A colour pair for the small icon-in-circle badges used throughout the
/// soft-card system (list-row leading icons, dashboard counters). Not the
/// same object as [FeChipStyle]: a badge has no border and is meant to be
/// looked at from across the room, so its background sits at 12-15% alpha
/// rather than the chip's flat pastel-50 fill.
@immutable
class FeBadgeStyle {
  const FeBadgeStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

/// Soft icon-badge accents, one per broad "kind" of thing a badge might
/// represent. Deliberately *not* wired to [FeOrderTypeColors] or
/// [FeStatusColors] — those two are locked to the web's literal palettes:
/// this is a separate decorative layer that composes the same underlying
/// hues at badge alpha, so a change here can never touch a tested value.
@immutable
class FeAccents extends ThemeExtension<FeAccents> {
  const FeAccents();

  final FeBadgeStyle orange = const FeBadgeStyle(
    background: Color(0x1FF97316),
    foreground: AppColors.orange600,
  );
  final FeBadgeStyle emerald = const FeBadgeStyle(
    background: Color(0x1F10B981),
    foreground: AppColors.emerald600,
  );
  final FeBadgeStyle blue = const FeBadgeStyle(
    background: Color(0x1F3B82F6),
    foreground: AppColors.blue600,
  );
  final FeBadgeStyle purple = const FeBadgeStyle(
    background: Color(0x1FA855F7),
    foreground: AppColors.purple600,
  );
  final FeBadgeStyle rose = const FeBadgeStyle(
    background: Color(0x1FE11D48),
    foreground: AppColors.rose600,
  );
  final FeBadgeStyle amber = const FeBadgeStyle(
    background: Color(0x1FD97706),
    foreground: AppColors.amber600,
  );
  final FeBadgeStyle slate = const FeBadgeStyle(
    background: Color(0x1F334155),
    foreground: AppColors.slate700,
  );

  @override
  FeAccents copyWith() => const FeAccents();

  @override
  FeAccents lerp(ThemeExtension<FeAccents>? other, double t) => this;
}

extension FeThemeAccess on BuildContext {
  FeStatusColors get chips => Theme.of(this).extension<FeStatusColors>()!;
  FeSpacing get space => Theme.of(this).extension<FeSpacing>()!;
  FeRadii get radii => Theme.of(this).extension<FeRadii>()!;
  FeMetrics get metrics => Theme.of(this).extension<FeMetrics>()!;
  FeMotion get motion => Theme.of(this).extension<FeMotion>()!;
  FeOrderTypeColors get orderTypeColors =>
      Theme.of(this).extension<FeOrderTypeColors>()!;
  FeAccents get accents => Theme.of(this).extension<FeAccents>()!;
}
