import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_extensions.dart';
import 'motion.dart';

/// The portal's one surface treatment: a soft, floating card. Depth comes
/// from a wide low-opacity shadow rather than a border — the "card floats a
/// millimetre off the page" look shared by every reference screen — so the
/// default has no visible border at all; pass [borderColor] only where a
/// screen genuinely needs a hairline (e.g. an already-white sheet on a white
/// background, where the shadow alone reads too weak to separate them).
///
/// [dark] paints the "hero" variant instead: the same card shape filled with
/// [AppColors.ink] and white text, used for the one or two summary cards per
/// screen that should read as the headline rather than a peer of the cards
/// around it (the dashboard's greeting card, a balance-style total).
class TechCard extends StatelessWidget {
  const TechCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.onTap,
    this.accentTop,
    this.dark = false,
    this.radius,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  final Color? accentTop;
  final bool dark;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? context.radii.xl);
    // The accent stripe is a drawn band, not a thicker top border side: a
    // BoxDecoration may only round a border whose sides all match, and giving
    // one side its own width and colour makes Flutter throw mid-paint — the
    // background lands, the border does not, and the card's contents never
    // draw at all.
    final card = Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.ink : AppColors.white,
        borderRadius: r,
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: dark ? FeElevation.floating : FeElevation.soft,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Children fill the card's width, as they did when the padding was
          // the decorated box itself.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accentTop != null)
              SizedBox(height: 4, child: ColoredBox(color: accentTop!)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: r, onTap: onTap, child: card),
      ),
    );
  }
}

/// The portal's universal loader: a 32 px orange partial ring.
class TechSpinner extends StatelessWidget {
  const TechSpinner({
    super.key,
    this.size = 32,
    this.color = AppColors.orange600,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    ),
  );
}

class TechEmptyState extends StatelessWidget {
  const TechEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor = AppColors.gray400,
    this.iconSize = 48,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) => TechCard(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        Container(
          height: iconSize + 24,
          width: iconSize + 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: iconSize * 0.6, color: iconColor),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.gray600, fontWeight: FontWeight.w600),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );
}

/// Pill chip used for status and priority. Colors come from FeStatusColors,
/// which is locked to the web's literal palettes and untouched by this — the
/// only thing that changed here is the chrome around those colours: a
/// softer, mostly-borderless pill instead of a hard 1px outline.
class TechChip extends StatelessWidget {
  const TechChip({
    super.key,
    required this.label,
    required this.style,
    this.uppercase = true,
    this.borderRadius,
  });

  final String label;
  final FeChipStyle style;
  final bool uppercase;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: style.background,
      borderRadius: borderRadius ?? BorderRadius.circular(999),
    ),
    child: Text(
      uppercase ? label.toUpperCase() : label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: style.foreground,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// A small icon inside a soft-tinted circle — the "leading badge" pattern
/// used on list rows (order type, checklist state) and dashboard counters.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.style,
    this.size = 40,
    this.iconSize = 18,
  });

  final IconData icon;
  final FeBadgeStyle style;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    height: size,
    width: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
    child: Icon(icon, size: iconSize, color: style.foreground),
  );
}

/// Screens not yet built in this phase.
class PhasePlaceholder extends StatelessWidget {
  const PhasePlaceholder({super.key, required this.title, required this.phase});

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: TechEmptyState(
        icon: Icons.construction_outlined,
        title: '$title — not built yet',
        subtitle: 'Scheduled for $phase of the port plan.',
      ),
    ),
  );
}
