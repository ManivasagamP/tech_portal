import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/capture/capture_services.dart';
import '../../domain/snag.dart';
import '../../state/snag_controller.dart';
import '../../theme/fe_colors.dart';

/// UC-6/UC-7 — the "ghost" camera: the before photo floats semi-transparent
/// over the live preview, so the after photo is taken from the same spot and
/// angle. A before/after pair shot from two different angles proves nothing;
/// one shot through the same frame is the evidence a DLP dispute or a
/// retention release actually turns on.
///
/// Returns the captured [CapturedPhoto] via `Navigator.pop`, like
/// `CameraCaptureScreen`. The opacity slider lets the user fade the ghost
/// out to see the live scene clearly, then back in to line it up.
class GhostCameraScreen extends ConsumerStatefulWidget {
  const GhostCameraScreen({super.key, required this.before, required this.title});

  final SnagEvidence? before;
  final String title;

  @override
  ConsumerState<GhostCameraScreen> createState() => _GhostCameraScreenState();
}

class _GhostCameraScreenState extends ConsumerState<GhostCameraScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  String? _error;
  File? _ghost;
  String? _ghostUrl;
  double _opacity = 0.4;
  var _torch = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    final before = widget.before;
    if (before != null) {
      ref.read(snagMediaProvider).localFile(before).then((f) {
        if (!mounted) return;
        setState(() {
          if (f == null) {
            _ghostUrl = before.url;
          } else {
            _ghost = f;
          }
        });
      });
    }
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'no camera');
        return;
      }
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final c = CameraController(rear, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _camera = c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (state == AppLifecycleState.inactive && c != null && c.value.isInitialized) {
      c.dispose();
      setState(() => _camera = null);
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _camera;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final bytes = await compute(downscaleJpeg, await file.readAsBytes());
      if (!mounted) return;
      Navigator.of(context).pop(CapturedPhoto(bytes: bytes, fileName: 'after.jpg'));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleTorch() async {
    final c = _camera;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = _camera;
    Widget? ghost;
    if (_ghost != null) {
      ghost = Image.file(_ghost!, fit: BoxFit.cover);
    } else if (_ghostUrl != null) {
      ghost = Image.network(_ghostUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_error != null)
            Center(
              child: Text(
                'fieldVerify.camera_unavailable'.getString(context),
                style: const TextStyle(color: Colors.white),
              ),
            )
          else if (c == null || !c.value.isInitialized)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.previewSize?.height ?? 1080,
                height: c.value.previewSize?.width ?? 1920,
                child: CameraPreview(c),
              ),
            ),
          if (ghost != null) IgnorePointer(child: Opacity(opacity: _opacity, child: ghost)),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _torch ? LucideIcons.flashlight : LucideIcons.flashlightOff,
                        color: _torch ? FeColors.warning : Colors.white,
                      ),
                      onPressed: _toggleTorch,
                    ),
                  ],
                ),
                if (ghost != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.ghost, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'snags.ghost_hint'.getString(context),
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (ghost != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.eyeOff, color: Colors.white70, size: 16),
                        Expanded(
                          child: Slider(
                            value: _opacity,
                            min: 0,
                            max: 0.85,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            onChanged: (v) => setState(() => _opacity = v),
                          ),
                        ),
                        const Icon(LucideIcons.eye, color: Colors.white70, size: 16),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24, top: 8),
                  child: GestureDetector(
                    onTap: _shoot,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _busy ? Colors.white54 : FeColors.success,
                        ),
                        child: const Icon(LucideIcons.check, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
