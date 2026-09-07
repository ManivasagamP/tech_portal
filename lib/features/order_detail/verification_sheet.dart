import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/capture/capture_services.dart';
import '../../state/checklist_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';

/// What the technician captured before a session may start or end.
class VerificationResult {
  const VerificationResult({this.photo, this.location});

  final CapturedPhoto? photo;
  final CapturedLocation? location;
}

enum VerificationMode { start, end }

/// Gate in front of a timer session. Nothing is sent until every required
/// piece is captured — the button stays locked otherwise.
class VerificationSheet extends ConsumerStatefulWidget {
  const VerificationSheet({
    super.key,
    required this.mode,
    required this.requireFaceCapture,
    required this.requireLocation,
  });

  final VerificationMode mode;
  final bool requireFaceCapture;
  final bool requireLocation;

  @override
  ConsumerState<VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends ConsumerState<VerificationSheet> {
  CapturedPhoto? _photo;
  CapturedLocation? _location;
  String? _locationError;
  bool _locating = false;

  bool get _ready =>
      (!widget.requireFaceCapture || _photo != null) &&
      (!widget.requireLocation || _location != null);

  @override
  void initState() {
    super.initState();
    // The web starts acquiring a fix as soon as the dialog opens, so the
    // technician is not left waiting after taking the photo.
    if (widget.requireLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final location = await ref.read(locationCaptureProvider).current();
      if (!mounted) return;
      setState(() => _location = location);
    } on CaptureFailure catch (e) {
      if (!mounted) return;
      setState(() => _locationError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationError = 'Could not get your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _capture({required bool fromGallery}) async {
    final capture = ref.read(photoCaptureProvider);
    final photo = fromGallery
        ? await capture.pickFromGallery()
        : await capture.takeFacePhoto();
    if (photo == null || !mounted) return;
    setState(() => _photo = photo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 32,
                  width: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.orange600,
                    borderRadius: BorderRadius.circular(context.radii.lg),
                  ),
                  child: const Icon(LucideIcons.circleCheck,
                      size: 18, color: AppColors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.mode == VerificationMode.end
                        ? 'Session End Verification'
                        : 'Identity Verification',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.requireFaceCapture) ...[
              _PhotoPanel(
                photo: _photo,
                onRetake: () => _capture(fromGallery: false),
                onPick: () => _capture(fromGallery: true),
                onClear: () => setState(() => _photo = null),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.requireLocation) ...[
              _LocationPanel(
                location: _location,
                locating: _locating,
                error: _locationError,
                onRetry: _locate,
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _ready
                    ? () => Navigator.of(context).pop(
                          VerificationResult(photo: _photo, location: _location),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(
                  widget.mode == VerificationMode.end
                      ? 'End session now'
                      : 'Start task now',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (!_ready) ...[
              const SizedBox(height: 12),
              Text(
                'Complete the steps above to unlock task controls.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppColors.gray400),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({
    required this.photo,
    required this.onRetake,
    required this.onPick,
    required this.onClear,
  });

  final CapturedPhoto? photo;
  final VoidCallback onRetake;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VERIFICATION PHOTO',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.gray400,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.slate950,
              borderRadius: BorderRadius.circular(context.radii.sheet),
            ),
            child: photo == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.camera,
                            size: 36, color: AppColors.gray400),
                        const SizedBox(height: 12),
                        Text(
                          'Take a photo of yourself to confirm you are on site.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.gray300),
                        ),
                      ],
                    ),
                  )
                : Image.memory(photo!.bytes, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onRetake,
                icon: const Icon(LucideIcons.camera, size: 16),
                label: Text(photo == null ? 'Take photo' : 'Retake'),
              ),
            ),
            const SizedBox(width: 8),
            if (photo == null)
              OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(LucideIcons.upload, size: 16),
                label: const Text('Upload'),
              )
            else
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: const Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.location,
    required this.locating,
    required this.error,
    required this.onRetry,
  });

  final CapturedLocation? location;
  final bool locating;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (location != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.emerald50,
          borderRadius: BorderRadius.circular(context.radii.sheet),
          border: Border.all(color: AppColors.green200),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.mapPin, size: 20, color: AppColors.emerald600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOCATION RECORDED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.emerald700,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // The place name when the device resolved one, with the
                  // coordinates under it — the name is what a person reads
                  // back, the numbers are what the record is actually made of.
                  if (location!.placeLabel != null) ...[
                    Text(
                      location!.placeLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.emerald700,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    '${location!.latitude.toStringAsFixed(4)}, '
                    '${location!.longitude.toStringAsFixed(4)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: AppColors.emerald700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error == null ? AppColors.gray50 : AppColors.red50,
        borderRadius: BorderRadius.circular(context.radii.sheet),
        border: Border.all(
          color: error == null ? AppColors.gray200 : AppColors.red200,
        ),
      ),
      child: Row(
        children: [
          if (locating)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              error == null ? LucideIcons.mapPin : LucideIcons.triangleAlert,
              size: 20,
              color: error == null ? AppColors.gray400 : AppColors.red600,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              locating
                  ? 'Getting your location…'
                  : error ?? 'Location not captured yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: error == null ? AppColors.gray600 : AppColors.red700,
              ),
            ),
          ),
          if (!locating)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
