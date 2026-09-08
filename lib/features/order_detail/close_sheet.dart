import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/utils/dates.dart';
import '../../domain/downtime.dart';
import '../../domain/maintenance_record.dart';
import '../../state/close_controller.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';

/// The one screen that closes a job: how long the asset was down, and — for
/// Critical and High priority — why it went wrong. Submitting runs root cause,
/// then downtime, then the completion call.
class CloseSheet extends ConsumerStatefulWidget {
  const CloseSheet({
    super.key,
    required this.orderKey,
    required this.record,
    required this.predictedStart,
    this.manualHours,
  });

  final OrderKey orderKey;
  final MaintenanceRecord record;

  /// When the first checklist item was started. The downtime window defaults to
  /// this rather than to blank, because it is nearly always the right answer.
  final DateTime? predictedStart;
  final double? manualHours;

  @override
  ConsumerState<CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends ConsumerState<CloseSheet> {
  late final CloseSubmitter _submitter = CloseSubmitter(
    ref.read(closeRepositoryProvider),
  );
  final _notesController = TextEditingController();

  DateTime? _start;
  DateTime? _end;
  DowntimeImpact _impact = DowntimeImpact.fullOutage;

  /// Start and end are still the guess (first checklist start → now) rather
  /// than a real recorded window or something the technician typed. The reset
  /// button only appears once they have diverged from it.
  bool _predicted = true;

  /// A window already running on this record. It fixes the start time — that
  /// moment is recorded fact, not something to re-enter.
  DowntimeWindow? _openWindow;

  /// A window open on another record for the same asset. Informational only:
  /// each record owns its own window, so there is nothing to collide with.
  DowntimeWindow? _otherOpenWindow;
  bool _windowsApplied = false;

  String? _rootCause;
  String? _rootCauseError;

  /// Set when the server itself names `rootCause` as missing. Its answer beats
  /// our priority guess: a field error must never land on a control that is not
  /// on screen, which would leave the sheet unclosable with nothing to fix.
  bool _forceRcaVisible = false;

  bool _submitting = false;
  String? _message;

  bool get _rcaVisible =>
      rcaRequiredForPriority(widget.record.priority) || _forceRcaVisible;

  @override
  void initState() {
    super.initState();
    _start = widget.predictedStart ?? DateTime.now();
    _end = DateTime.now();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _applyPredicted() {
    setState(() {
      _start = widget.predictedStart ?? DateTime.now();
      _end = DateTime.now();
      _predicted = true;
    });
  }

  /// Folds the fetched history in once. Doing it in `build` would overwrite the
  /// technician's own edits every time the provider rebuilt.
  void _applyWindows(List<DowntimeWindow> history) {
    if (_windowsApplied) return;
    _windowsApplied = true;

    final stillOpen = history.where((w) => w.isOpen).toList();
    final mine = stillOpen
        .where(
          (w) =>
              w.source == widget.record.type.downtimeSource &&
              w.sourceId == widget.record.id,
        )
        .firstOrNull;

    _openWindow = mine;
    _otherOpenWindow = mine == null ? stillOpen.firstOrNull : null;
    if (mine != null) {
      _start = mine.startedAt;
      _end = DateTime.now();
      _predicted = false;
    }
  }

  Future<void> _pick({required bool isStart}) async {
    final current = (isStart ? _start : _end) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _predicted = false;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _message = null;
      _rootCauseError = null;
    });

    final result = await _submitter.submit(
      CloseRequest(
        type: widget.record.type,
        recordId: widget.record.id,
        rootCause: _rootCause,
        rcaNotes: _notesController.text.trim(),
        downtimeStart: _start,
        downtimeEnd: _end,
        impact: _impact,
        hasAsset: widget.record.assetId != null,
        hasOpenWindow: _openWindow != null,
        manualHours: widget.manualHours,
      ),
    );
    if (!mounted) return;

    switch (result) {
      case CloseSucceeded(:final queued):
        await ref
            .read(orderDetailControllerProvider(widget.orderKey).notifier)
            .refresh();
        if (!mounted) return;
        Navigator.of(context).pop(
          queued
              ? 'Close saved offline. It will be submitted when you are back online.'
              : 'Job closed. Downtime and root cause captured.',
        );
      case CloseAlreadyClosed():
        await ref
            .read(orderDetailControllerProvider(widget.orderKey).notifier)
            .refresh();
        if (!mounted) return;
        Navigator.of(context)
            .pop('This job was already closed by someone else.');
      case CloseRejected(
        :final needsRootCause,
        :final needsChecklist,
        :final message,
      ):
        setState(() {
          _submitting = false;
          if (needsRootCause) {
            _forceRcaVisible = true;
            _rootCauseError = 'Required at Critical or High priority.';
          }
          // The server's own text is written for whoever is calling the API —
          // the root-cause refusal names an endpoint and a request field. Say
          // it in the technician's terms when the gate is one we know, and
          // fall back to the server's wording only for a gate we do not.
          _message = needsRootCause
              ? 'Choose why it went wrong before closing this job.'
              : needsChecklist
              ? 'Complete at least one checklist task before closing.'
              : message;
        });
      case CloseFailed(:final message):
        setState(() {
          _submitting = false;
          _message = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetId = widget.record.assetId;
    final history = assetId == null
        ? const AsyncValue<List<DowntimeWindow>>.data([])
        : ref.watch(downtimeHistoryProvider(assetId));
    history.whenData(_applyWindows);

    // The modal route caps this sheet at a fixed fraction of the screen and
    // never accounts for the keyboard — without this padding the keyboard
    // just overlaps the sheet's bottom edge, hiding the Notes field and the
    // Cancel/Confirm buttons below it, neither of which can scroll into view
    // on their own (mirrors order_chat_sheet.dart's composer).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.titleMedium(
                          'Close ${widget.record.type.label.toLowerCase()}',
                          weight: FontWeight.w800,
                        ),
                        const SizedBox(height: 2),
                        AppText.bodySmall(
                          'Record how long the asset was down, and why it went '
                          'wrong if this is Critical or High priority.',
                          color: FeColors.ink2,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_message != null) ...[
                      _CloseBanner(
                        message: _message!,
                        onDismiss: () => setState(() => _message = null),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AppText.titleSmall(
                      '1. How long it was down',
                      weight: FontWeight.w700,
                    ),
                    const SizedBox(height: 4),
                    AppText.bodySmall(
                      'Downtime is the window the asset could not do its job — '
                      'not how long the repair took.',
                      color: FeColors.ink2,
                    ),
                    const SizedBox(height: 12),
                    if (assetId == null)
                      const _CloseNote(
                        icon: LucideIcons.info,
                        text:
                            'No asset is linked to this record, so there is no '
                            'downtime to record.',
                      )
                    else if (history.isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else ...[
                      if (_openWindow != null)
                        _CloseNote(
                          icon: LucideIcons.timerReset,
                          text:
                              'Downtime has been running on this record since '
                              '${formatDateTimeShort(_openWindow!.startedAt)}. '
                              'Closing it with the end time below.',
                        )
                      else if (_otherOpenWindow != null)
                        _CloseNote(
                          icon: LucideIcons.triangleAlert,
                          tone: FeColors.warning,
                          text:
                              '${_otherOpenWindow!.reference ?? 'Another record'} '
                              'has this asset marked down since '
                              '${formatDateTimeShort(_otherOpenWindow!.startedAt)}. '
                              'That is recorded separately — you can still record '
                              'downtime here.',
                        )
                      else if (_predicted)
                        const _CloseNote(
                          icon: LucideIcons.timerReset,
                          text:
                              'Predicted from your checklist times — down since '
                              'the first task was started, running again as of '
                              'now. Edit below if that is wrong.',
                        ),
                      if (_openWindow == null && !_predicted)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _applyPredicted,
                            icon: const Icon(LucideIcons.timerReset, size: 14),
                            label: const AppText('Reset to predicted'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _DateTimeField(
                        label: 'Down since',
                        value: _start,
                        // A running window's start is recorded fact.
                        onTap: _openWindow != null || _submitting
                            ? null
                            : () => _pick(isStart: true),
                      ),
                      const SizedBox(height: 12),
                      _DateTimeField(
                        label: 'Running again',
                        value: _end,
                        onTap: _submitting ? null : () => _pick(isStart: false),
                      ),
                      const SizedBox(height: 12),
                      AppText.labelMedium('Impact', color: FeColors.ink2),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<DowntimeImpact>(
                        initialValue: _impact,
                        isExpanded: true,
                        items: [
                          for (final option in DowntimeImpact.values)
                            DropdownMenuItem(
                              value: option,
                              child: AppText(
                                option.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) =>
                                  setState(() => _impact = value ?? _impact),
                      ),
                    ],
                    if (_rcaVisible) ...[
                      const SizedBox(height: 24),
                      AppText.titleSmall(
                        '2. Why it went wrong',
                        weight: FontWeight.w700,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _rootCause,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Root cause',
                          errorText: _rootCauseError,
                          // The default single line clipped this to "…at …",
                          // which told the technician nothing.
                          errorMaxLines: 3,
                        ),
                        items: [
                          for (final option in kRootCauseOptions)
                            DropdownMenuItem(
                              value: option,
                              child: AppText(humanizeRootCause(option)),
                            ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) => setState(() {
                                _rootCause = value;
                                _rootCauseError = null;
                              }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        enabled: !_submitting,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText:
                              'What actually happened — the story a '
                              'dropdown cannot hold.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: FeColors.line),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const AppText('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: FeColors.success,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const AppText('Confirm & close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tap target that reads like a field. The platform pickers do the editing;
/// a technician in gloves is not typing a timestamp.
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = onTap == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText.labelMedium(label, color: FeColors.ink2),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: locked ? FeColors.page : FeColors.panel,
              borderRadius: BorderRadius.circular(context.radii.md),
              border: Border.all(color: FeColors.line),
            ),
            child: Row(
              children: [
                Icon(
                  locked ? LucideIcons.lock : LucideIcons.calendar,
                  size: 16,
                  color: FeColors.ink2,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppText.bodyMedium(
                    value == null ? 'Not set' : formatDateTimeShort(value!),
                    color: value == null ? FeColors.ink2 : FeColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseNote extends StatelessWidget {
  const _CloseNote({
    required this.icon,
    required this.text,
    this.tone = FeColors.info,
  });

  final IconData icon;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone == FeColors.warning
          ? FeColors.warningSoft
          : FeColors.infoSoft,
      borderRadius: BorderRadius.circular(context.radii.md),
      border: Border.all(
        color: tone == FeColors.warning
            ? FeColors.warningSoft
            : FeColors.infoSoft,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 10),
        Expanded(child: AppText.bodySmall(text, color: FeColors.ink2)),
      ],
    ),
  );
}

/// Refusals show here rather than in a SnackBar: the messenger belongs to the
/// screen underneath, so its message would render behind this sheet.
class _CloseBanner extends StatelessWidget {
  const _CloseBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
    decoration: BoxDecoration(
      color: FeColors.dangerSoft,
      borderRadius: BorderRadius.circular(context.radii.md),
      border: Border.all(color: FeColors.dangerSoft),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.triangleAlert, size: 16, color: FeColors.danger),
        const SizedBox(width: 10),
        Expanded(child: AppText.bodySmall(message, color: FeColors.danger)),
        IconButton(
          onPressed: onDismiss,
          visualDensity: VisualDensity.compact,
          icon: const Icon(LucideIcons.x, size: 14, color: FeColors.danger),
        ),
      ],
    ),
  );
}
