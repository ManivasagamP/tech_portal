import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../../theme/fe_colors.dart';
import '../../../widgets/app_text.dart';
import 'permit_sheet.dart';

/// Stop work (docs/permit-to-work.md): the one button always visible on a
/// live permit, for anyone — a gas alarm, an unsafe condition, or any other
/// reason to down tools right now. Returns the reason text, or null if the
/// technician backed out.
Future<String?> showStopWorkSheet(BuildContext context) => showPermitSheet<String>(context, const _StopWorkSheet());

class _StopWorkSheet extends StatefulWidget {
  const _StopWorkSheet();

  @override
  State<_StopWorkSheet> createState() => _StopWorkSheetState();
}

class _StopWorkSheetState extends State<_StopWorkSheet> {
  static const _keys = ['gas_alarm', 'unsafe_condition', 'emergency', 'scope_changed', 'other'];
  String? _chip;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _reason {
    final parts = [
      if (_chip != null) 'permits.stop_reason.$_chip'.getString(context),
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' — ');
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PermitSheetGrabber(),
          AppText.titleMedium('permits.stop_work_title'.getString(context), weight: FontWeight.w800),
          const SizedBox(height: 4),
          AppText.bodySmall('permits.stop_work_subtitle'.getString(context), color: FeColors.ink2),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in _keys)
                ChoiceChip(
                  selected: _chip == k,
                  onSelected: (_) => setState(() => _chip = _chip == k ? null : k),
                  label: Text('permits.stop_reason.$k'.getString(context)),
                  showCheckmark: false,
                  selectedColor: FeColors.danger,
                  labelStyle: TextStyle(
                    color: _chip == k ? Colors.white : FeColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'permits.stop_work_note_hint'.getString(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FeColors.danger, minimumSize: const Size.fromHeight(48)),
            onPressed: _reason == null ? null : () => Navigator.of(context).pop(_reason),
            child: Text('permits.stop_work_confirm'.getString(context)),
          ),
        ],
      ),
    ),
  );
}
