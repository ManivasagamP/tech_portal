import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../domain/snag.dart';
import '../../state/providers.dart';
import '../../state/snag_controller.dart';
import '../../theme/fe_colors.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/fe_header.dart';
import 'widgets/snag_visuals.dart';

/// UC-12 — a floor's plan with every snag pinned on it, coloured by
/// severity. In pick mode ([pick] true) a tap drops a crosshair and
/// "Use this spot" pops a [SnagPin]. Seeing the existing pins while placing
/// a new one is itself a duplicate check: a red dot already on that corner
/// is hard to miss.
///
/// Reuses FR-2.8's plan metadata + on-disk image cache, so a floor opened
/// once online works offline afterwards.
class SnagPlanScreen extends ConsumerStatefulWidget {
  const SnagPlanScreen({
    super.key,
    required this.floorId,
    this.buildingId,
    this.focusSnagId,
    this.pick = false,
    this.initial,
  });

  final String floorId;
  final String? buildingId;
  final String? focusSnagId;
  final bool pick;
  final SnagPin? initial;

  @override
  ConsumerState<SnagPlanScreen> createState() => _SnagPlanScreenState();
}

class _SnagPlanScreenState extends ConsumerState<SnagPlanScreen> {
  File? _image;
  Size? _size;
  String? _error;
  var _loading = true;
  SnagPin? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final record = await ref.read(floorPlanRepositoryProvider).get(widget.floorId);
      if (!mounted) return;
      final url = record?.imageUrl;
      if (url == null) {
        setState(() {
          _loading = false;
          _error = 'snags.plan_none'.getString(context);
        });
        return;
      }
      final cache = ref.read(floorPlanImageCacheProvider);
      final file = await cache.cached(url) ?? await cache.getOrDownload(url);
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _image = file;
        _size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'snags.plan_offline'.getString(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snags = widget.buildingId == null
        ? const <Snag>[]
        : (ref.watch(snagsProvider(widget.buildingId)).valueOrNull ?? const <Snag>[])
              .where((s) => s.pin?.floorId == widget.floorId && s.status.isLive)
              .toList();
    return Scaffold(
      backgroundColor: FeColors.page,
      appBar: FeHeader(
        title: widget.pick ? 'snags.pin_title'.getString(context) : 'snags.plan_title'.getString(context),
      ),
      body: _loading
          ? const TechSpinner()
          : _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: TechEmptyState(icon: LucideIcons.mapPinOff, title: _error!),
            )
          : Column(
              children: [
                if (widget.pick)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: AppText.bodySmall('snags.pin_hint'.getString(context)),
                  ),
                Expanded(
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _size!.width / _size!.height,
                        child: LayoutBuilder(
                          builder: (context, box) => GestureDetector(
                            onTapUp: widget.pick
                                ? (d) => setState(
                                    () => _picked = SnagPin(
                                      floorId: widget.floorId,
                                      x: (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
                                      y: (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
                                    ),
                                  )
                                : null,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(child: Image.file(_image!, fit: BoxFit.fill)),
                                for (final s in snags)
                                  _pin(
                                    box,
                                    s.pin!,
                                    color: SnagVisuals.priorityColor(s.priority),
                                    focused: s.id == widget.focusSnagId,
                                    onTap: widget.pick ? null : () => context.push(Routes.snagDetail(s.id)),
                                  ),
                                if (_picked != null)
                                  Positioned(
                                    left: _picked!.x * box.maxWidth - 16,
                                    top: _picked!.y * box.maxHeight - 32,
                                    child: const Icon(LucideIcons.mapPin, size: 32, color: FeColors.primary),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.pick)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: _picked == null ? null : () => Navigator.of(context).pop(_picked),
                        icon: const Icon(LucideIcons.check),
                        label: Text('snags.pin_use'.getString(context)),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _pin(BoxConstraints box, SnagPin pin, {required Color color, bool focused = false, VoidCallback? onTap}) {
    final d = focused ? 22.0 : 14.0;
    return Positioned(
      left: pin.x * box.maxWidth - d / 2,
      top: pin.y * box.maxHeight - d / 2,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: focused ? 3 : 2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: focused ? 12 : 4)],
          ),
        ),
      ),
    );
  }
}
