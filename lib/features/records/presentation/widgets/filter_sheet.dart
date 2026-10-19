import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:flutter/material.dart';

const _dateRangeLabels = {
  DateRangeOption.allTime: 'Todo o período',
  DateRangeOption.thisWeek: 'Esta semana',
  DateRangeOption.thisMonth: 'Este mês',
};

const _entryTypeLabels = {
  EntrySource.manual: 'Manual',
  EntrySource.audio: 'Áudio',
  EntrySource.photo: 'Foto',
  EntrySource.chat: 'Chat',
};

/// "Sheet de filtro" (prototype-extract.md §2.4). Seeded with the screen's
/// *current* applied criteria so re-opening reflects what's already applied,
/// not a reset form.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.initialDateRange,
    required this.initialEntryTypes,
  });

  final DateRangeOption initialDateRange;
  final Set<EntrySource> initialEntryTypes;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late DateRangeOption _dateRange = widget.initialDateRange;
  late Set<EntrySource> _entryTypes = {...widget.initialEntryTypes};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtrar registros', style: DesignTokens.textTitleSm),
            const SizedBox(height: DesignTokens.spacingMd),
            Text('TIPO DE ENTRADA', style: _groupLabelStyle),
            const SizedBox(height: DesignTokens.spacingSm),
            Wrap(
              spacing: DesignTokens.spacingSm,
              children: [
                for (final source in EntrySource.values)
                  _FilterChip(
                    label: _entryTypeLabels[source]!,
                    selected: _entryTypes.contains(source),
                    onSelected: () => setState(() {
                      _entryTypes = {..._entryTypes};
                      if (!_entryTypes.remove(source)) _entryTypes.add(source);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text('PERÍODO', style: _groupLabelStyle),
            const SizedBox(height: DesignTokens.spacingSm),
            Wrap(
              spacing: DesignTokens.spacingSm,
              children: [
                for (final option in DateRangeOption.values)
                  _FilterChip(
                    label: _dateRangeLabels[option]!,
                    selected: _dateRange == option,
                    onSelected: () => setState(() => _dateRange = option),
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingLg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  (dateRange: _dateRange, entryTypes: _entryTypes),
                ),
                child: const Text('Aplicar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final _groupLabelStyle = DesignTokens.textMonoCaption.copyWith(
    color: DesignTokens.colorTextSecondary,
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      shape: const StadiumBorder(),
      selectedColor: DesignTokens.colorPrimary,
      backgroundColor: Colors.transparent,
      side: BorderSide(
        color: selected ? DesignTokens.colorPrimary : DesignTokens.colorBorder,
      ),
      labelStyle: DesignTokens.textLabelMd.copyWith(
        color: selected ? DesignTokens.colorOnPrimary : DesignTokens.colorTextSecondary,
      ),
    );
  }
}
