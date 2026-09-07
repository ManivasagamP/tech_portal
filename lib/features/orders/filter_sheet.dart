import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/orders_controller.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';

const _priorityOptions = ['Critical', 'High', 'Medium', 'Low'];

/// Bottom sheet holding sort, timeframe, priority and status. Edits are local
/// until Apply; Reset clears and closes in one step, as on the web.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.filters,
    required this.statusOptions,
  });

  final OrderFilters filters;
  final List<String> statusOptions;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late OrderFilters _local = widget.filters;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: FeColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppText.titleMedium(
                    'Filters',
                    weight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Sort Order'),
                  _SegmentedRow(
                    options: const ['Newest First', 'Oldest First'],
                    selectedIndex: _local.sortOrder == SortOrder.desc ? 0 : 1,
                    onSelected: (index) => setState(() {
                      _local = _local.copyWith(
                        sortOrder: index == 0 ? SortOrder.desc : SortOrder.asc,
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('Timeframe'),
                  _SegmentedRow(
                    options: const ['All dates', 'Overdue', 'Due Today'],
                    fontSize: 10,
                    selectedIndex: DateFilter.values.indexOf(_local.dateFilter),
                    onSelected: (index) => setState(() {
                      _local = _local.copyWith(
                        dateFilter: DateFilter.values[index],
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('Priority Level'),
                  _ToggleGrid(
                    options: _priorityOptions,
                    selected: _local.priority,
                    onToggle: (value) => setState(() {
                      _local = _local.priority == value
                          ? _local.copyWith(clearPriority: true)
                          : _local.copyWith(priority: value);
                    }),
                  ),
                  if (widget.statusOptions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionLabel('Task Status'),
                    _ToggleGrid(
                      options: widget.statusOptions,
                      selected: _local.status,
                      fontSize: 10,
                      onToggle: (value) => setState(() {
                        _local = _local.status == value
                            ? _local.copyWith(clearStatus: true)
                            : _local.copyWith(status: value);
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: FeColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const OrderFilters()),
                    child: const AppText('Reset'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_local),
                    child: const AppText('Apply Filters'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppText(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: FeColors.ink2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
        ),
      );
}

class _SegmentedRow extends StatelessWidget {
  const _SegmentedRow({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.fontSize = 12,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: FeColors.page,
          borderRadius: BorderRadius.circular(context.radii.card),
          border: Border.all(color: FeColors.line),
        ),
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: context.motion.sheetClose,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selectedIndex
                          ? FeColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(context.radii.lg),
                      boxShadow: i == selectedIndex ? FeElevation.sm : null,
                    ),
                    child: AppText(
                      options[i],
                      align: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                            color: i == selectedIndex
                                ? Colors.white
                                : FeColors.ink2,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Two-column grid of toggles; tapping the active one clears it.
class _ToggleGrid extends StatelessWidget {
  const _ToggleGrid({
    required this.options,
    required this.selected,
    required this.onToggle,
    this.fontSize = 12,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onToggle;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 32 - 8) / 2,
              child: GestureDetector(
                onTap: () => onToggle(option),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option == selected
                        ? FeColors.primary.withValues(alpha: 0.08)
                        : FeColors.panel,
                    borderRadius: BorderRadius.circular(context.radii.card),
                    border: Border.all(
                      width: 2,
                      color: option == selected
                          ? FeColors.primary
                          : FeColors.line,
                    ),
                  ),
                  child: AppText(
                    option,
                    align: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          color: option == selected
                              ? FeColors.primary
                              : FeColors.ink2,
                        ),
                  ),
                ),
              ),
            ),
        ],
      );
}
