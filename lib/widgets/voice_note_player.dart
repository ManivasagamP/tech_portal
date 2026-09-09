import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  @override
  void dispose() {
    _player?.dispose();
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
      final duration = await player.setUrl(widget.audioUrl);
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
        title: const AppText('Delete voice note?'),
        content: const AppText('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const AppText('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: FeColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const AppText('Delete'),
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
              'Saved on this device — uploads when you are back online',
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
                  'This recording could not be loaded.',
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
                tooltip: 'Delete voice note',
                onPressed: _run,
                icon: const Icon(LucideIcons.trash2,
                    size: 14, color: FeColors.ink2),
              ),
      );
}
