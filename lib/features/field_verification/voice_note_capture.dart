import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/capture/capture_services.dart';
import '../../theme/fe_colors.dart';
import '../../widgets/app_text.dart';
import '../../widgets/voice_note_player.dart';
import '../../widgets/voice_waveform.dart';

/// FR-3.6 — an attached voice note: tap to record, see a live waveform,
/// tap to stop, then play it back. Same proven record → waveform →
/// playback pattern the work-order voice note already uses
/// (`record_voice_note.dart`), reused as-is rather than reinvented.
///
/// Deliberately audio-only, no auto-transcription into the notes field.
/// An earlier attempt tried running the mic recorder *and* an on-device
/// speech recognizer at once to fill notes automatically from the
/// recording. Real-device testing proved that combination broken —
/// pulling the recorded file and inspecting its actual audio track (not
/// just the UI) showed a properly-captured clip is ~3.3 real seconds of
/// audio for a ~4 second recording when the recorder runs alone, but
/// only ~0.14 seconds — essentially silence — when the recognizer runs
/// alongside it. Android hands the microphone almost exclusively to
/// whichever one is "listening," so the recorder starves. There is also
/// no way to transcribe an *already-recorded* file after the fact — the
/// recognizer only works on a live mic stream — so once the recording
/// half has to run alone, so does the whole feature. Confirmed as the
/// intended, final shape (not a fallback) after presenting this evidence.
///
/// The notes field itself stays exactly as free-text and editable as it
/// already was; a technician who wants the recording's words in Notes
/// listens back and types it themselves.
class VoiceNoteCapture extends StatefulWidget {
  const VoiceNoteCapture({super.key});

  @override
  State<VoiceNoteCapture> createState() => _VoiceNoteCaptureState();
}

class _VoiceNoteCaptureState extends State<VoiceNoteCapture> {
  final _voice = VoiceCapture();
  var _recording = false;
  VoiceRecording? _clip;
  Stream<Amplitude>? _amplitudeStream;

  @override
  void dispose() {
    if (_recording) _voice.cancel();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      final clip = await _voice.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _amplitudeStream = null;
        if (clip != null) _clip = clip;
      });
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _clip = null);
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _toggle,
              style: OutlinedButton.styleFrom(
                backgroundColor: _recording ? FeColors.dangerSoft : FeColors.primary.withValues(alpha: 0.08),
                foregroundColor: _recording ? FeColors.danger : FeColors.primary,
                side: BorderSide(color: _recording ? FeColors.dangerSoft : FeColors.primary),
              ),
              icon: Icon(_recording ? LucideIcons.square : LucideIcons.mic, size: 16),
              label: AppText(
                (_recording
                        ? 'fieldVerify.voice_listening'
                        : clip == null
                        ? 'fieldVerify.voice_note'
                        : 'fieldVerify.voice_note_replace')
                    .getString(context),
              ),
            ),
            if (_recording && _amplitudeStream != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: VoiceWaveform(amplitudeStream: _amplitudeStream!, color: FeColors.primary),
              ),
            ],
          ],
        ),
        if (clip != null && !_recording) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FeColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FeColors.line),
            ),
            child: VoiceNotePlayer(
              audioUrl: clip.dataUrl,
              durationSeconds: clip.duration.inSeconds,
              onDelete: _delete,
            ),
          ),
        ],
      ],
    );
  }
}
