import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import '../../app/env.dart';
import '../../app/router.dart';
import '../../core/utils/qr_payload.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';
import '../../widgets/fe_header.dart';

/// Reads the QR stickers on assets, work orders and material bins.
///
/// A hit never navigates on its own — it shows what it found and waits for a
/// deliberate tap. Scanning is easy to do by accident when a camera is
/// sweeping a plant room, and being thrown into an unrelated record mid-job
/// loses whatever the technician was doing.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  /// 400 ms between detections and QR-only decoding, matching the web scanner.
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
    formats: const [BarcodeFormat.qrCode],
  );

  /// Only our own codes are held on screen; external content is acted on and
  /// forgotten, so this is never a [ScannedExternal].
  ScannedRecord? _result;
  String? _resultRaw;
  var _paused = false;
  var _processing = false;

  /// The last value read, held for four seconds. A QR code sitting in frame
  /// re-decodes many times a second; without this the same sticker would fire
  /// the handler over and over.
  String? _lastScanned;
  Timer? _cooldown;

  @override
  void dispose() {
    _cooldown?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRaw(String raw) async {
    if (_processing || raw == _lastScanned) return;

    setState(() {
      _processing = true;
      _lastScanned = raw;
    });
    _cooldown?.cancel();
    _cooldown = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _lastScanned = null);
    });

    final resolution = resolveScannedValue(raw);
    await _buzz();
    if (!mounted) return;

    switch (resolution) {
      case final ScannedRecord record:
        // One of ours. Hold it on screen behind a confirm tap.
        setState(() {
          _result = record;
          _resultRaw = raw;
          _processing = false;
        });
      case ScannedExternal(:final value, :final isUrl):
        setState(() => _processing = false);
        if (isUrl) {
          await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
          if (mounted) _toast('scanner.opened_in_browser'.getString(context));
        } else {
          // Not a link and not ours — show the text and let the person read it.
          _toast(value);
        }
    }
  }

  Future<void> _buzz() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 200);
      }
    } catch (_) {
      // A missing motor is not worth reporting.
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText(message)),
      );

  Future<void> _togglePause() async {
    if (_paused) {
      await _controller.start();
    } else {
      await _controller.stop();
    }
    if (mounted) setState(() => _paused = !_paused);
  }

  /// Decoding a photo covers the code that is behind a guard, above head
  /// height, or on a panel the camera cannot be held steady against.
  Future<void> _scanFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() => _processing = true);
    try {
      final capture = await _controller.analyzeImage(file.path);
      final raw = capture?.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (raw == null) {
        if (mounted) {
          setState(() => _processing = false);
          _toast('scanner.no_qr_in_picture'.getString(context));
        }
        return;
      }
      // A picked image is a deliberate act, so it bypasses the cooldown.
      _lastScanned = null;
      if (mounted) setState(() => _processing = false);
      await _handleRaw(raw);
    } catch (error) {
      if (mounted) {
        setState(() => _processing = false);
        _toast('scanner.picture_unreadable'.getString(context));
      }
    }
  }

  void _openResult() {
    final result = _result;
    if (result == null) return;

    if (result.isPublic) {
      // Asset and material sheets are web pages; there is no native screen.
      context.pushReplacement(
        Routes.webPage(
          '${Env.webBaseUrl}${result.path}',
          title: result.label,
        ),
      );
    } else {
      context.pushReplacement(result.path);
    }
  }

  void _resume() {
    setState(() {
      _result = null;
      _resultRaw = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FeHeader(
        showBack: true,
        titleWidget: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: FeColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.qrCode, size: 18, color: FeColors.primary),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppText.titleSmall(
                  'scanner.title'.getString(context),
                  weight: FontWeight.w700,
                ),
                AppText.caption(
                  _paused
                      ? 'scanner.paused'.getString(context)
                      : 'scanner.looking_for_code'.getString(context),
                  color: FeColors.ink2,
                ),
              ],
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on
                    ? 'scanner.torch_off'.getString(context)
                    : 'scanner.torch_on'.getString(context),
                icon: Icon(
                  on ? LucideIcons.flashlight : LucideIcons.flashlightOff,
                  size: 18,
                  color: on ? FeColors.warning : Colors.white.withValues(alpha: 0.7),
                ),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(context.radii.scanner),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _controller,
                            errorBuilder: (context, error) => _CameraError(
                              message: _describe(context, error),
                            ),
                            onDetect: (capture) {
                              if (_paused || _processing || result != null) {
                                return;
                              }
                              final raw = capture.barcodes
                                  .map((barcode) => barcode.rawValue)
                                  .whereType<String>()
                                  .firstOrNull;
                              if (raw != null) _handleRaw(raw);
                            },
                          ),
                          const _Brackets(),
                          if (result != null)
                            _HitOverlay(
                              label: result.label,
                              detail: result.path,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (result == null)
                _Controls(
                  paused: _paused,
                  onTogglePause: _togglePause,
                  onGallery: _scanFromGallery,
                )
              else
                _OpenButton(
                  label: context.formatString(
                    'scanner.open_result'.getString(context),
                    [result.label.toLowerCase()],
                  ),
                  onOpen: _openResult,
                  onDismiss: _resume,
                ),
              if (_resultRaw != null) ...[
                const SizedBox(height: 12),
                AppText.caption(
                  _resultRaw!,
                  align: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(BuildContext context, MobileScannerException error) =>
      switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'scanner.camera_permission_denied'.getString(context),
        MobileScannerErrorCode.unsupported =>
          'scanner.camera_unsupported'.getString(context),
        _ => 'scanner.camera_start_failed'.getString(context),
      };
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.cameraOff,
                  size: 40, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              AppText(
                message,
                align: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

/// The four corner marks that tell the technician where to aim.
class _Brackets extends StatelessWidget {
  const _Brackets();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              for (final corner in _corners)
                Align(
                  alignment: corner,
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      border: Border(
                        top: corner.y < 0 ? _side : BorderSide.none,
                        bottom: corner.y > 0 ? _side : BorderSide.none,
                        left: corner.x < 0 ? _side : BorderSide.none,
                        right: corner.x > 0 ? _side : BorderSide.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  static const _side = BorderSide(color: Color(0x4DFFFFFF), width: 4);

  static const _corners = [
    Alignment.topLeft,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomRight,
  ];
}

class _HitOverlay extends StatelessWidget {
  const _HitOverlay({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        color: FeColors.primary.withValues(alpha: 0.85),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.circleCheck,
                  size: 36, color: FeColors.primary),
            ),
            const SizedBox(height: 16),
            AppText(
              '$label found',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            AppText(
              detail,
              align: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 11),
            ),
          ],
        ),
      );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.paused,
    required this.onTogglePause,
    required this.onGallery,
  });

  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: onTogglePause,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      paused ? FeColors.primary : FeColors.panel,
                  foregroundColor:
                      paused ? Colors.white : FeColors.ink,
                ),
                icon: Icon(paused ? LucideIcons.play : LucideIcons.pause,
                    size: 16),
                label: AppText(
                  paused
                      ? 'scanner.resume'.getString(context)
                      : 'scanner.pause'.getString(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: onGallery,
                style: OutlinedButton.styleFrom(
                  // The app theme fills outlined buttons white for the light
                  // screens; on this dark one that hides the label entirely.
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                icon: const Icon(LucideIcons.image, size: 16),
                label: AppText('scanner.photo'.getString(context)),
              ),
            ),
          ),
        ],
      );
}

class _OpenButton extends StatelessWidget {
  const _OpenButton({
    required this.label,
    required this.onOpen,
    required this.onDismiss,
  });

  final String label;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            height: 60,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: FeColors.primary,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(LucideIcons.externalLink, size: 20),
              label: AppText(label),
            ),
          ),
          TextButton(
            onPressed: onDismiss,
            child: AppText(
              'scanner.scan_something_else'.getString(context),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      );
}
