import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../theme/fe_ar_colors.dart';
import '../../../theme/fe_colors.dart';
import '../../../widgets/app_text.dart';
import '../../../widgets/motion.dart';
import '../ar_ui.dart';

/// The AR overlay's building blocks: glass controls that float on the camera
/// and white cards for decisions (canvas rows 6–8). Touch targets are at
/// least 48 px and primary buttons 54 px (§2.9 "Everywhere").

/// A 48 px rounded glass button with an icon — back, menu, the phone's edge
/// tools. [label] is always set: it becomes the tooltip and the semantics
/// label, so an icon-only phone control is still named for screen readers.
class ArGlassButton extends StatelessWidget {
  const ArGlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 48,
    this.active = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final bool active;

  /// A small count dot (e.g. queued writes).
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final fg = active ? FeColors.ink : Colors.white;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: PressableScale(
          child: Material(
            color: active ? Colors.white : FeArColors.glass,
            borderRadius: BorderRadius.circular(size * 0.3),
            child: InkWell(
              borderRadius: BorderRadius.circular(size * 0.3),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 21, color: onTap == null ? fg.withValues(alpha: 0.4) : fg),
                    if (badge != null && badge! > 0)
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: FeColors.warning, borderRadius: BorderRadius.circular(99)),
                          child: AppText.caption('${badge!}', color: FeColors.ink, weight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled glass pill over the camera ("Corner 1 · column C-2").
class ArGlassChip extends StatelessWidget {
  const ArGlassChip({super.key, required this.text, this.icon, this.iconColor, this.strong = false, this.onTap});

  final String text;
  final IconData? icon;
  final Color? iconColor;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: strong ? FeArColors.glassStrong : FeArColors.glass,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor ?? FeArColors.onGlass),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: AppText.bodySmall(
              text,
              color: FeArColors.onGlass,
              weight: FontWeight.w600,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// Tones of the honest alignment badge (§2.7).
enum ArBadgeTone { none, placed, locked, manual, mismatch, drifting }

/// The alignment badge. Amber = placed, green = locked (measured), grey =
/// adjusted by hand, red = the site disagrees with the model. It never shows
/// a tone the fit did not earn.
class ArStatusBadge extends StatelessWidget {
  const ArStatusBadge({super.key, required this.tone, required this.text, this.onTap, this.dense = false});

  final ArBadgeTone tone;
  final String text;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tone) {
      ArBadgeTone.locked => (FeArColors.lockedBg, FeArColors.lockedFg, ArIcons.lock),
      ArBadgeTone.placed => (FeArColors.placedBg, FeArColors.placedFg, null),
      ArBadgeTone.drifting => (FeArColors.placedBg, FeArColors.placedFg, ArIcons.reSnap),
      ArBadgeTone.manual => (FeArColors.manualBg, FeArColors.manualFg, ArIcons.fineTune),
      ArBadgeTone.mismatch => (FeArColors.mismatchBg, FeArColors.mismatchFg, ArIcons.warning),
      ArBadgeTone.none => (FeArColors.glass, FeArColors.onGlass, ArIcons.info),
    };
    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minHeight: dense ? 40 : 44),
      padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (tone == ArBadgeTone.placed)
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: FeArColors.placedDot, shape: BoxShape.circle),
            )
          else if (icon != null)
            Icon(icon, size: 15, color: tone == ArBadgeTone.locked ? FeArColors.lockedIcon : fg),
          const SizedBox(width: 8),
          Flexible(
            child: AppText.bodySmall(
              text,
              color: fg,
              weight: FontWeight.w700,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      label: text,
      child: onTap == null ? badge : GestureDetector(onTap: onTap, child: badge),
    );
  }
}

/// The 54 px primary action. Lives in the thumb zone of every card.
class ArPrimaryButton extends StatelessWidget {
  const ArPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color = FeColors.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Flexible(
                    child: AppText.label(
                      label,
                      color: Colors.white,
                      weight: FontWeight.w700,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The quiet partner of [ArPrimaryButton] inside a white card ("Not now",
/// "Carry on").
class ArSecondaryButton extends StatelessWidget {
  const ArSecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: FeArColors.manualBg,
          foregroundColor: FeColors.ink,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 8)],
            Flexible(
              child: AppText.label(label, color: FeColors.ink, weight: FontWeight.w700, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// A button that sits directly on the camera ("Other method", "Board hard to
/// see? Turn on the torch").
class ArOnCameraButton extends StatelessWidget {
  const ArOnCameraButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 48});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: FeArColors.glass,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 17, color: Colors.white), const SizedBox(width: 8)],
            Flexible(
              child: AppText.label(label, color: Colors.white, weight: FontWeight.w600, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// A white decision card floating over the camera (setup steps, prompts).
class ArCard extends StatelessWidget {
  const ArCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 24});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FeColors.panel,
      elevation: 0,
      borderRadius: BorderRadius.circular(radius),
      shadowColor: Colors.black26,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8))],
          color: FeColors.panel,
        ),
        child: child,
      ),
    );
  }
}

/// Setup progress dots ("Corner 1 of 2" ● ○).
class ArStepDots extends StatelessWidget {
  const ArStepDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsetsDirectional.only(start: 6),
            width: i == index ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= index ? FeColors.primary : FeColors.line,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

/// A small green "done" row inside a white card ("Snapped · 90° outside corner").
class ArSuccessRow extends StatelessWidget {
  const ArSuccessRow({super.key, required this.text, this.icon = ArIcons.check});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: FeArColors.lockedBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: FeArColors.lockedIcon),
          const SizedBox(width: 8),
          Expanded(child: AppText.bodySmall(text, color: FeArColors.lockedFg, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// An amber or red hint row inside a white card, always with a next step.
class ArHintRow extends StatelessWidget {
  const ArHintRow({super.key, required this.text, this.danger = false, this.icon});

  final String text;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = danger ? FeArColors.mismatchBg : FeArColors.placedBg;
    final fg = danger ? FeArColors.mismatchFg : FeArColors.placedFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? (danger ? ArIcons.warning : ArIcons.info), size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: AppText.bodySmall(text, color: fg, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The eyebrow above a group ("TICK THE MODELS TO SHOW TOGETHER").
class ArEyebrow extends StatelessWidget {
  const ArEyebrow(this.text, {super.key, this.onDark = false});

  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return AppText.caption(
      text.toUpperCase(),
      color: onDark ? FeArColors.onGlassMuted : FeColors.ink2,
      weight: FontWeight.w700,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.8),
    );
  }
}

/// The ever-present Demo mode banner: nobody should mistake sample data for
/// their building.
class ArDemoBanner extends StatelessWidget {
  const ArDemoBanner({super.key, this.onExit});

  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FeColors.warning,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onExit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(ArIcons.demo, size: 14, color: FeColors.ink),
              const SizedBox(width: 6),
              AppText.caption('ar.demo.banner'.getString(context), color: FeColors.ink, weight: FontWeight.w800),
              if (onExit != null) ...[
                const SizedBox(width: 8),
                AppText.caption('ar.demo.exit'.getString(context), color: FeColors.ink, weight: FontWeight.w600),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A scrim-safe centred title over the camera ("Hold still").
class ArCameraTitle extends StatelessWidget {
  const ArCameraTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppText.headlineSmall(
      text,
      color: Colors.white,
      weight: FontWeight.w700,
      align: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
      ),
    );
  }
}

/// An arrow-like icon that points the reading direction: flipped in Arabic
/// so "next" and "back" never point the wrong way.
class ArDirectionalIcon extends StatelessWidget {
  const ArDirectionalIcon(this.icon, {super.key, this.size = 18, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: Directionality.of(context) == TextDirection.rtl,
    child: Icon(icon, size: size, color: color),
  );
}
