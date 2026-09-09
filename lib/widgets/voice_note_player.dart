import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/fe_colors.dart';
import 'app_text.dart';

/// A recording made offline carries a placeholder token instead of a URL until
/// the queue uploads its bytes. Pointing a player at that token would request a
/// file that does not exist, so it is shown as pending instead.
bool isPendingAudio(String url) => url.startsWith('__pending_audio_');

String formatClipDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

bool _isDataUrl(String url) => url.startsWith('data:');

/// Decodes a `data:<mime>;base64,<data>` string (a freshly-sent or
/// history-loaded chat voice note — see `VoiceRecording.dataUrl`) to bytes
/// and writes them to a fresh file in the temp directory, returning its path.
/// `just_audio`'s `setFilePath` is the well-supported cross-platform way to
/// play in-memory audio; there is no equivalent guarantee for handing it a
/// raw `data:` URI.
Future<String> _dataUrlToTempFile(String dataUrl) async {
  final match = RegExp(r'^data:[^;,]+;base64,(.+)$', dotAll: true)
      .firstMatch(dataUrl);
  final bytes = match == null ? null : base64Decode(match.group(1)!);
  if (bytes == null) {
    throw const FormatException('Not a valid data: audio URL');
  }
  final directory = await getTemporaryDirectory();
  final path =
      '${directory.path}/chat-voice-${DateTime.now().microsecondsSinceEpoch}.aac';
  final file = File(path);
  await file.writeAsBytes(bytes);
  return path;
}

class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.audioUrl,
    this.durationSeconds,
    this.onDelete,
  });

  final String audioUrl;
  final int? durationSeconds;

  /// Omit on read-only surfaces so a recording cannot be erased there.
  final Future<void> Function()? onDelete;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  AudioPlayer? _player;
  bool _loading = false;
  bool _failed = false;
  Duration _position = Duration.zero;
  Duration? _total;
  bool _playing = false;

  /// Set only when [_ensurePlayer] decoded a `data:` URL to a temp file —
  /// cleaned up on dispose so repeatedly opening a chat thread with voice
  /// notes does not leave files behind.
  String? _tempFilePath;

  @override
  void dispose() {
    _player?.dispose();
    final path = _tempFilePath;
    if (path != null) {
      File(path).delete().catchError((_) async => File(path));
    }
    super.dispose();
  }

  /// The clip is only fetched when it is actually played — a task can carry
  /// several notes and a technician is usually on mobile data.
  Future<AudioPlayer?> _ensurePlayer() async {
    if (_player != null) return _player;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final player = AudioPlayer();
    try {
      // A chat voice note arrives as an in-memory `data:<mime>;base64,<data>`
      // string (see `VoiceRecording.dataUrl`), not a fetchable URL — native
      // support for playing a `data:` URI directly via `setUrl` is
      // inconsistent across platforms, so it is decoded and written to a
      // temp file first, the same well-supported path `setFilePath` already
      // uses for on-device recordings.
      Duration? duration;
      if (_isDataUrl(widget.audioUrl)) {
        final tempPath = await _dataUrlToTempFile(widget.audioUrl);
        _tempFilePath = tempPath;
        duration = await player.setFilePath(tempPath);
      } else {
        duration = await player.setUrl(widget.audioUrl);
      }
      player.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      });
      player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state.playing);
        if (state.processingState == ProcessingState.completed) {
          player.seek(Duration.zero);
          player.pause();
        }
      });
      if (!mounted) {
        await player.dispose();
        return null;
      }
      setState(() {
        _player = player;
        _total = duration;
        _loading = false;
      });
      return player;
    } catch (_) {
      await player.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return null;
    }
  }

  Future<void> _toggle() async {
    final player = await _ensurePlayer();
    if (player == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FeColors.panel,
        title: AppText('widgets.delete_voice_note_title'.getString(context)),
        content: AppText('common.cannot_be_undone'.getString(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: AppText('common.cancel'.getString(context)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: FeColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: AppText('common.delete'.getString(context)),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stated = widget.durationSeconds == null
        ? null
        : Duration(seconds: widget.durationSeconds!);

    if (isPendingAudio(widget.audioUrl)) {
      return Row(
        children: [
          const Icon(LucideIcons.cloudUpload,
              size: 14, color: FeColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: AppText.caption(
              'widgets.voice_note_pending_upload'.getString(context),
              color: FeColors.warning,
            ),
          ),
          if (stated != null)
            AppText.caption(
              formatClipDuration(stated),
              color: FeColors.ink2,
            ),
          // Deleting a queued note is safe: the queue replays in order, so the
          // removal lands after the add and wins.
          if (widget.onDelete != null) _DeleteButton(onTap: _confirmDelete),
        ],
      );
    }

    final total = _total ?? stated;
    final progress = (total == null || total.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          height: 32,
          width: 32,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: _failed ? null : _toggle,
                  icon: Icon(
                    _failed
                        ? LucideIcons.triangleAlert
                        : _playing
                            ? LucideIcons.pause
                            : LucideIcons.play,
                    size: 18,
                    color: _failed ? FeColors.danger : FeColors.primary,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _failed
              ? AppText.caption(
                  'widgets.voice_note_load_error'.getString(context),
                  color: FeColors.danger,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: FeColors.line,
                    valueColor:
                        const AlwaysStoppedAnimation(FeColors.primary),
                  ),
                ),
        ),
        if (total != null && !_failed) ...[
          const SizedBox(width: 8),
          AppText(
            formatClipDuration(_playing || _position > Duration.zero
                ? _position
                : total),
            style: theme.textTheme.labelSmall?.copyWith(
              color: FeColors.ink2,
            ),
          ),
        ],
        if (widget.onDelete != null) _DeleteButton(onTap: _confirmDelete),
      ],
    );
  }
}

class _DeleteButton extends StatefulWidget {
  const _DeleteButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        width: 32,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                padding: EdgeInsets.zero,
                tooltip: 'widgets.delete_voice_note_tooltip'.getString(context),
                onPressed: _run,
                icon: const Icon(LucideIcons.trash2,
                    size: 14, color: FeColors.ink2),
              ),
      );
}
