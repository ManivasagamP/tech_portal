import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/capture/capture_services.dart';
import '../../state/checklist_controller.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';
import '../../widgets/voice_note_player.dart';
import '../../widgets/voice_waveform.dart';

/// A work order carries one spoken note of its own, separate from the
/// per-item checklist notes. Recording again replaces the previous one.
class RecordVoiceNote extends ConsumerStatefulWidget {
  const RecordVoiceNote({
    super.key,
    required this.orderKey,
    required this.audioUrl,
  });

  final OrderKey orderKey;
  final String? audioUrl;

  @override
  ConsumerState<RecordVoiceNote> createState() => _RecordVoiceNoteState();
}

class _RecordVoiceNoteState extends ConsumerState<RecordVoiceNote> {
  final _voice = VoiceCapture();
  bool _recording = false;
  bool _saving = false;
  Stream<Amplitude>? _amplitudeStream;

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  void _report(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: AppText(message)));
  }

  Future<void> _toggleRecording() async {
    final controller = ref.read(
      checklistControllerProvider(widget.orderKey).notifier,
    );

    if (_recording) {
      final recording = await _voice.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _amplitudeStream = null;
        _saving = recording != null;
      });
      if (recording == null) {
        _report('Nothing was recorded.');
        return;
      }
      final message = await controller.setRecordVoiceNote(voice: recording);
      if (mounted) setState(() => _saving = false);
      _report(message?.text ?? 'Your recording is attached to this order.');
      return;
    }

    try {
      final directory = await getTemporaryDirectory();
      await _voice.start(directory.path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _amplitudeStream = _voice.amplitudeStream();
      });
    } on CaptureFailure catch (e) {
      _report(e.message);
    }
  }

  Future<void> _delete() async {
    final message = await ref
        .read(checklistControllerProvider(widget.orderKey).notifier)
        .setRecordVoiceNote();
    _report(message?.text ?? 'The recording has been removed.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = widget.audioUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _toggleRecording,
              style: OutlinedButton.styleFrom(
                backgroundColor: _recording
                    ? FeColors.dangerSoft
                    : FeColors.primary.withValues(alpha: 0.1),
                foregroundColor: _recording
                    ? FeColors.danger
                    : FeColors.primary,
                side: BorderSide(
                  color: _recording ? FeColors.dangerSoft : FeColors.primary,
                ),
              ),
              icon: Icon(
                _recording ? LucideIcons.square : LucideIcons.mic,
                size: 16,
              ),
              label: AppText(
                _saving
                    ? 'Saving…'
                    : _recording
                    ? 'Stop recording'
                    : url == null
                    ? 'Record voice note'
                    : 'Replace voice note',
              ),
            ),
            if (_recording && _amplitudeStream != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: VoiceWaveform(
                  amplitudeStream: _amplitudeStream!,
                  color: FeColors.primary,
                ),
              ),
            ],
          ],
        ),
        if (url != null && url.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FeColors.page,
              borderRadius: BorderRadius.circular(context.radii.card),
              border: Border.all(color: FeColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'YOUR VOICE NOTE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: FeColors.ink2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                VoiceNotePlayer(audioUrl: url, onDelete: _delete),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
