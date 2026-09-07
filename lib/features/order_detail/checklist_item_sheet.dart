import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/capture/capture_services.dart';
import '../../core/utils/dates.dart';
import '../../domain/checklist.dart';
import '../../state/checklist_controller.dart';
import '../../state/providers.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/voice_note_player.dart';
import 'verification_sheet.dart';

/// Everything a technician does to one task: run its timer, tick it off, add
/// notes and photos.
class ChecklistItemSheet extends ConsumerStatefulWidget {
  const ChecklistItemSheet({
    super.key,
    required this.orderKey,
    required this.index,
    required this.requireFaceCapture,
    required this.requireLocation,
  });

  final OrderKey orderKey;
  final int index;
  final bool requireFaceCapture;
  final bool requireLocation;

  @override
  ConsumerState<ChecklistItemSheet> createState() => _ChecklistItemSheetState();
}

class _ChecklistItemSheetState extends ConsumerState<ChecklistItemSheet> {
  final _noteController = TextEditingController();
  final _voice = VoiceCapture();
  bool _recording = false;

  /// Shown inside the sheet. A SnackBar cannot be used here: the messenger
  /// belongs to the Scaffold underneath, so its message renders behind this
  /// sheet and the technician sees nothing at all when a write is rejected.
  String? _message;

  /// Whether [_message] is a "saved offline" notice. Once the queue drains the
  /// notice is stale — it would keep promising a sync that already happened.
  bool _messageIsQueued = false;

  @override
  void dispose() {
    _noteController.dispose();
    _voice.dispose();
    super.dispose();
  }

  ChecklistController get _controller =>
      ref.read(checklistControllerProvider(widget.orderKey).notifier);

  void _report(ActionOutcome? outcome) {
    if (outcome == null || !mounted) return;
    setState(() {
      _message = outcome.text;
      _messageIsQueued = outcome.queued;
    });
  }

  /// A session start or end may be gated behind a photo and a location fix.
  Future<VerificationResult?> _verify(VerificationMode mode) async {
    if (!widget.requireFaceCapture && !widget.requireLocation) {
      return const VerificationResult();
    }
    return showModalBottomSheet<VerificationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.radii.sheet),
        ),
      ),
      builder: (context) => VerificationSheet(
        mode: mode,
        requireFaceCapture: widget.requireFaceCapture,
        requireLocation: widget.requireLocation,
      ),
    );
  }

  Future<void> _toggleTimer(ChecklistItem item) async {
    final mode = item.isRunning ? VerificationMode.end : VerificationMode.start;
    final verification = await _verify(mode);
    if (verification == null) return;

    _report(
      mode == VerificationMode.end
          ? await _controller.stopSession(
              widget.index,
              facePhoto: verification.photo,
              location: verification.location,
            )
          : await _controller.startSession(
              widget.index,
              facePhoto: verification.photo,
              location: verification.location,
            ),
    );
  }

  Future<void> _addPhoto({required bool fromGallery}) async {
    final capture = ref.read(photoCaptureProvider);
    final photo = fromGallery
        ? await capture.pickFromGallery()
        : await capture.takeJobPhoto();
    if (photo == null) return;
    _report(await _controller.addPhoto(widget.index, photo));
  }

  Future<void> _sendNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    _noteController.clear();
    _report(await _controller.addNote(widget.index, text: text));
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final recording = await _voice.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (recording == null) {
        _report(const ActionOutcome.failed('Nothing was recorded.'));
        return;
      }
      _report(
        await _controller.addNote(
          widget.index,
          text: _noteController.text.trim(),
          voice: recording,
        ),
      );
      _noteController.clear();
      return;
    }

    try {
      final directory = await getTemporaryDirectory();
      await _voice.start(directory.path);
      if (!mounted) return;
      setState(() => _recording = true);
    } on CaptureFailure catch (e) {
      _report(ActionOutcome.failed(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    // "Saved offline" is only true while the write is still queued. When the
    // queue empties the write has landed, so the notice goes with it.
    ref.listen(pendingMutationCountProvider, (_, next) {
      if (_messageIsQueued && next.valueOrNull == 0) {
        setState(() {
          _message = null;
          _messageIsQueued = false;
        });
      }
    });

    final state = ref.watch(checklistControllerProvider(widget.orderKey));
    if (widget.index >= state.items.length) return const SizedBox.shrink();

    final item = state.items[widget.index];
    final busy = state.busyIndex == widget.index;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: busy || (item.isCompleted && !item.isRunning)
                        ? null
                        : () => _toggleTimer(item),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: item.isRunning
                          ? AppColors.red500
                          : AppColors.orange600,
                    ),
                    icon: Icon(
                      item.isRunning ? LucideIcons.pause : LucideIcons.play,
                      size: 16,
                    ),
                    label: Text(
                      item.isRunning
                          ? 'Pause'
                          : item.sessions.isEmpty
                          ? 'Start Timer'
                          : 'Start New Session',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async =>
                              _report(await _controller.toggle(widget.index)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: item.isCompleted
                          ? AppColors.green600
                          : null,
                      foregroundColor: item.isCompleted
                          ? AppColors.white
                          : AppColors.gray700,
                    ),
                    child: Text(
                      item.isCompleted ? 'Mark Incomplete' : 'Mark Complete',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (_message != null)
            _SheetMessage(
              message: _message!,
              onDismiss: () => setState(() {
                _message = null;
                _messageIsQueued = false;
              }),
            ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                _TimeLog(item: item),
                const SizedBox(height: 16),
                _Notes(item: item),
                const SizedBox(height: 16),
                _Attachments(
                  item: item,
                  onAdd: () => _addPhoto(fromGallery: false),
                  onPick: () => _addPhoto(fromGallery: true),
                  onRemove: (url) async =>
                      _report(await _controller.removePhoto(widget.index, url)),
                ),
              ],
            ),
          ),
          _NoteComposer(
            controller: _noteController,
            recording: _recording,
            enabled: !busy,
            onSend: _sendNote,
            onToggleRecording: _toggleRecording,
          ),
        ],
      ),
    );
  }
}

class _TimeLog extends StatelessWidget {
  const _TimeLog({required this.item});

  final ChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = item.sessions.reversed.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.orange50,
        borderRadius: BorderRadius.circular(context.radii.xl),
        boxShadow: FeElevation.tinted(AppColors.orange600),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.clock,
                size: 16,
                color: AppColors.orange700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Time Tracking',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.orange900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orange100,
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                child: Text(
                  'Total: ${formatMinutesAsHours(item.timeSpent ?? 0)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.orange700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sessions.isEmpty)
            Text(
              'No sessions yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.orange700,
              ),
            )
          else
            for (var i = 0; i < sessions.length; i++)
              _SessionRow(session: sessions[i], number: sessions.length - i),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.number});

  final ChecklistSession session;
  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGeo = session.latitude != null && session.longitude != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(context.radii.card),
        boxShadow: FeElevation.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orange50,
                  borderRadius: BorderRadius.circular(context.radii.sm),
                ),
                child: Text(
                  'SESSION $number',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: AppColors.orange600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Verified in and verified out. `cameraOff` used to mark the
              // end capture, which read as "no photo was taken" — the exact
              // opposite of what its presence means.
              if (session.faceCaptureUrl != null)
                const Icon(
                  LucideIcons.logIn,
                  size: 12,
                  color: AppColors.orange400,
                ),
              if (session.endFaceCaptureUrl != null)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    LucideIcons.logOut,
                    size: 12,
                    color: AppColors.orange400,
                  ),
                ),
              const Spacer(),
              Text(
                session.isRunning
                    ? 'Running'
                    : formatMinutesAsHours(session.timeSpent ?? 0),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: session.isRunning
                      ? AppColors.amber600
                      : AppColors.gray600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            session.startTime == null
                ? '—'
                : '${formatSessionDate(session.startTime!)} '
                      '${formatSessionTime(session.startTime!)}'
                      '${session.endTime == null ? '' : ' → ${formatSessionTime(session.endTime!)}'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.gray600,
              fontFamily: 'monospace',
            ),
          ),
          if (hasGeo) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  LucideIcons.mapPin,
                  size: 11,
                  color: AppColors.gray400,
                ),
                const SizedBox(width: 4),
                // The place name where one was resolved, the coordinates
                // otherwise — a technician reading their own history wants
                // "where was I", and the numbers only answer that on a map.
                Expanded(
                  child: Text(
                    session.placeLabel ??
                        '${session.latitude!.toStringAsFixed(4)}, '
                            '${session.longitude!.toStringAsFixed(4)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: AppColors.gray500,
                      fontFamily: session.placeLabel == null
                          ? 'monospace'
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.item});

  final ChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = [
      if (item.legacyComment != null) ChecklistNote(text: item.legacyComment!),
      ...item.comments,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.messageSquare,
              size: 16,
              color: AppColors.gray600,
            ),
            const SizedBox(width: 8),
            Text(
              'Notes',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (notes.isEmpty)
          Text(
            'No notes yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.gray500,
            ),
          )
        else
          for (final note in notes)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(context.radii.card),
                border: Border.all(color: AppColors.gray200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.text.isNotEmpty)
                    Text(note.text, style: theme.textTheme.bodySmall),
                  if (note.audioUrl != null) ...[
                    if (note.text.isNotEmpty) const SizedBox(height: 8),
                    VoiceNotePlayer(
                      audioUrl: note.audioUrl!,
                      durationSeconds: note.durationSeconds,
                    ),
                  ],
                  if (note.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatHistoryTimestamp(note.createdAt!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.item,
    required this.onAdd,
    required this.onPick,
    required this.onRemove,
  });

  final ChecklistItem item;
  final VoidCallback onAdd;
  final VoidCallback onPick;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.paperclip,
              size: 16,
              color: AppColors.gray600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Photos',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onPick,
              tooltip: 'Choose from gallery',
              icon: const Icon(LucideIcons.image, size: 18),
            ),
            IconButton(
              onPressed: onAdd,
              tooltip: 'Take a photo',
              icon: const Icon(LucideIcons.camera, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (item.attachments.isEmpty)
          Text(
            'No photos attached.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.gray500,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final url in item.attachments)
                _AttachmentTile(
                  url: url,
                  urls: item.attachments,
                  onRemove: () => onRemove(url),
                ),
            ],
          ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.url,
    required this.urls,
    required this.onRemove,
  });

  final String url;
  final List<String> urls;
  final VoidCallback onRemove;

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white,
        title: const Text('Remove this photo?'),
        content: const Text('It will be taken off this task.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red600,
              foregroundColor: AppColors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final pending = url.startsWith('__pending_photo_');

    return SizedBox(
      height: 88,
      width: 88,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: pending
                ? null
                : () => showPhotoViewer(context, urls: urls, initial: url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(context.radii.card),
              child: pending
                  ? Container(
                      color: AppColors.gray100,
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.cloudUpload,
                        size: 20,
                        color: AppColors.gray500,
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => Container(
                        color: AppColors.gray100,
                        alignment: Alignment.center,
                        child: const Icon(
                          LucideIcons.image,
                          size: 20,
                          color: AppColors.gray400,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => _confirmRemove(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.x,
                  size: 12,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteComposer extends StatelessWidget {
  const _NoteComposer({
    required this.controller,
    required this.recording,
    required this.enabled,
    required this.onSend,
    required this.onToggleRecording,
  });

  final TextEditingController controller;
  final bool recording;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onToggleRecording;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(top: BorderSide(color: AppColors.gray200)),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled && !recording,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: recording
                  ? 'Recording… tap the mic to stop'
                  : 'Add a note',
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: enabled ? onToggleRecording : null,
          tooltip: recording ? 'Stop recording' : 'Record a voice note',
          style: IconButton.styleFrom(
            backgroundColor: recording ? AppColors.red50 : null,
          ),
          icon: Icon(
            recording ? LucideIcons.square : LucideIcons.mic,
            size: 20,
            color: recording ? AppColors.red600 : AppColors.orange600,
          ),
        ),
        IconButton(
          onPressed: enabled && !recording ? onSend : null,
          tooltip: 'Send note',
          icon: const Icon(LucideIcons.send, size: 20),
        ),
      ],
    ),
  );
}

/// Inline feedback for an action taken in this sheet — a rejection from the
/// server, or confirmation that something was queued offline.
class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.amber50,
      borderRadius: BorderRadius.circular(context.radii.card),
      border: Border.all(color: AppColors.amber200),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.info, size: 16, color: AppColors.amber900),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.amber900),
          ),
        ),
        GestureDetector(
          onTap: onDismiss,
          child: const Icon(LucideIcons.x, size: 14, color: AppColors.amber900),
        ),
      ],
    ),
  );
}
