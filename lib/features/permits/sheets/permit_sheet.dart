import 'package:flutter/material.dart';

import '../../../theme/fe_colors.dart';

/// Shared bottom-sheet chrome for every PTW sheet — same shape/behaviour as
/// Snag Assistant's `_sheet` helper (features/snags/widgets/snag_sheets.dart),
/// duplicated locally rather than imported so the permits module has no
/// compile-time dependency on the snags one.
Future<T?> showPermitSheet<T>(BuildContext context, Widget child, {bool tall = false}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: FeColors.panel,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: tall ? SizedBox(height: MediaQuery.sizeOf(context).height * 0.85, child: child) : child,
  ),
);

class PermitSheetGrabber extends StatelessWidget {
  const PermitSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(color: FeColors.line, borderRadius: BorderRadius.circular(999)),
    ),
  );
}
