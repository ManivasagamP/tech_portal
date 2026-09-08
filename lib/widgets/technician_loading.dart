import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/env.dart';
import '../theme/fe_colors.dart';
import 'app_text.dart';

/// Premium industrial technician-themed loading animation & screen
class TechnicianLoadingView extends StatefulWidget {
  const TechnicianLoadingView({
    super.key,
    this.message = 'Loading your workspace...',
    this.submessage = 'Connecting…',
    this.showBrand = true,
  });

  final String message;
  final String submessage;
  final bool showBrand;

  @override
  State<TechnicianLoadingView> createState() => _TechnicianLoadingViewState();
}

class _TechnicianLoadingViewState extends State<TechnicianLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final val = _controller.value;
                return SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer pulsing radar ring
                      Transform.scale(
                        scale: 0.85 + (0.35 * math.sin(val * math.pi)),
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: FeColors.primaryLight.withValues(
                                alpha: 0.15 + 0.25 * (1 - val),
                              ),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      // Rotating dotted dashed ring
                      Transform.rotate(
                        angle: val * 2 * math.pi,
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: CircularProgressIndicator(
                            value: 0.75,
                            strokeWidth: 2,
                            strokeCap: StrokeCap.round,
                            valueColor: AlwaysStoppedAnimation(
                              FeColors.primaryLight.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      // Reverse rotating subtle ring
                      Transform.rotate(
                        angle: -val * 2 * math.pi,
                        child: SizedBox(
                          width: 82,
                          height: 82,
                          child: CircularProgressIndicator(
                            value: 0.4,
                            strokeWidth: 1.5,
                            strokeCap: StrokeCap.round,
                            valueColor: AlwaysStoppedAnimation(
                              FeColors.primary.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                      // Center solid technician badge
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [FeColors.ink, FeColors.primary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: FeColors.primary.withValues(alpha: 0.35),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          LucideIcons.hardHat,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            if (widget.showBrand) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: FeColors.infoSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: FeColors.primaryLight.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: FeColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppText.caption(
                      '${Env.brandName.toUpperCase()} FIELD OPS',
                      color: FeColors.ink,
                      weight: FontWeight.w600,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            AppText.title(
              widget.message,
              align: TextAlign.center,
              weight: FontWeight.w700,
            ),
            const SizedBox(height: 6),
            AppText.caption(
              widget.submessage,
              align: TextAlign.center,
              color: FeColors.ink2,
            ),
          ],
        ),
      ),
    );
  }
}
