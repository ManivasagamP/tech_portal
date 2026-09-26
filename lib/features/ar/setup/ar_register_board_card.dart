import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ar/marker_code.dart';
import '../../../state/ar_session_controller.dart';
import '../../../state/ar_setup_controller.dart';
import '../../../theme/fe_colors.dart';
import '../../../widgets/app_text.dart';
import '../ar_ui.dart';
import '../widgets/ar_chrome.dart';
import '../widgets/ar_status.dart';

/// TabRegister / PhRegister / I4Spare (AR-56, AR-43): "New board, not saved
/// yet". One decision in plain words, replacing GAMMA's "Unregistered QR
/// code. Do you want to edit QR codes?". Everything the phone measured is
/// shown (code, centre height, facing, print scale); only the name can be
/// typed, and it comes pre-filled from the room.
class ArRegisterBoardCard extends ConsumerStatefulWidget {
  const ArRegisterBoardCard({super.key, required this.tablet});

  final bool tablet;

  @override
  ConsumerState<ArRegisterBoardCard> createState() => _ArRegisterBoardCardState();
}

class _ArRegisterBoardCardState extends ConsumerState<ArRegisterBoardCard> {
  final _name = TextEditingController();
  var _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seeded here, not in initState: the translated wall word needs the
    // localisation scope, which initState can't read yet.
    if (_seeded) return;
    _seeded = true;
    _name.text = _defaultName(ref.read(arSetupProvider));
  }

  /// "Plant Room B · west wall" — the room it's in and the wall it's on.
  String _defaultName(ArSetupState setup) {
    final room = setup.pendingName;
    final n = setup.pendingNormalTile;
    if (room == null || n == null) return '';
    return '$room · ${arWallKey(n.x, n.z).getString(context)}';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(arSetupProvider);
    final demo = ref.watch(arSessionProvider.select((s) => s.demo));
    final ctrl = ref.read(arSetupProvider.notifier);
    final code = setup.pendingCode ?? '';
    final n = setup.pendingNormalTile;
    final scale = setup.pendingScalePct;
    final scaleOk = scale == null || (scale - 100).abs() <= 2;

    final facts = <Widget>[
      _Fact(label: 'ar.register.code'.getString(context), value: setup.pendingIsSpare ? MarkerCode.spareLabel(code) : MarkerCode.display(code)),
      if (setup.pendingHeightM != null)
        _Fact(label: 'ar.register.height'.getString(context), value: arMetres(context, setup.pendingHeightM!)),
      if (n != null) _Fact(label: 'ar.register.faces'.getString(context), value: arCompassKey(n.x, n.z).getString(context)),
      _Fact(
        label: 'ar.register.scale'.getString(context),
        value: scale == null ? 'ar.register.scale_unmeasured'.getString(context) : '${scale.round()}%${scaleOk ? ' ✓' : ''}',
        bad: !scaleOk,
      ),
    ];

    return ArCard(
      padding: EdgeInsets.all(widget.tablet ? 22 : 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: AlignmentDirectional.centerStart, child: ArSessionBadge()),
          const SizedBox(height: 12),
          AppText.title('ar.register.title'.getString(context), weight: FontWeight.w800),
          const SizedBox(height: 4),
          AppText.bodyMedium('ar.register.body'.getString(context), color: FeColors.ink2),
          if (!setup.pendingIsSpare) ...[
            const SizedBox(height: 10),
            ArHintRow(text: 'ar.register.unknown_board'.getString(context)),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'ar.register.name'.getString(context),
              hintText: 'ar.register.name_hint'.getString(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: facts),
          const SizedBox(height: 12),
          AppText.bodySmall('ar.register.derived_note'.getString(context), color: FeColors.ink2),
          if (!scaleOk) ...[
            const SizedBox(height: 8),
            ArHintRow(text: 'ar.register.scale_bad'.getString(context), danger: true),
          ],
          if (setup.saveError != null) ...[
            const SizedBox(height: 8),
            ArHintRow(text: setup.saveError!.getString(context), danger: true),
          ],
          if (demo) ...[
            const SizedBox(height: 8),
            AppText.caption('ar.demo.not_saved'.getString(context), color: FeColors.ink2),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 14,
                child: ArPrimaryButton(
                  label: 'ar.register.save'.getString(context),
                  icon: ArIcons.check,
                  busy: setup.saving,
                  onPressed: () => ctrl.saveBoard(_name.text),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 10, child: ArSecondaryButton(label: 'ar.common.not_now'.getString(context), onPressed: ctrl.notNow)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.bad = false});
  final String label;
  final String value;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bad ? FeColors.dangerSoft : FeColors.page,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bad ? FeColors.danger.withValues(alpha: 0.3) : FeColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText.caption(label, color: FeColors.ink2),
          AppText.bodyMedium(value, weight: FontWeight.w700, color: bad ? FeColors.danger : FeColors.ink),
        ],
      ),
    );
  }
}
