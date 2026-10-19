import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:cerne/features/records/presentation/bloc/records_bloc.dart';
import 'package:cerne/features/records/presentation/bloc/records_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

// Prototype's rgba(124,139,111,.18) — `colorSecondary` at 18% opacity.
const _chipTintBg = Color(0x2E7C8B6F);
// Prototype's #3F4A38 — a dark olive, distinct from any existing token.
const _chipTintText = Color(0xFF3F4A38);

/// "Filtros ativos" (prototype-extract.md §2.4). One removable chip per
/// currently-applied Filter Set criterion, plus a trailing "Limpar filtros"
/// link that clears both the Filter Set and any active search text (FR-006/
/// FR-007).
class ActiveFilterChipsRow extends StatelessWidget {
  const ActiveFilterChipsRow({super.key, required this.chips});

  final List<ActiveFilterChip> chips;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: DesignTokens.spacingSm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final chip in chips)
            Chip(
              label: Text(_labelFor(chip)),
              onDeleted: () => context.read<RecordsBloc>().add(FilterChipRemoved(chip)),
              backgroundColor: _chipTintBg,
              labelStyle: DesignTokens.textLabelMd.copyWith(
                fontSize: 12,
                color: _chipTintText,
              ),
              side: BorderSide.none,
              deleteIconColor: _chipTintText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
            ),
          TextButton(
            onPressed: () => context.read<RecordsBloc>().add(const FiltersAndSearchCleared()),
            child: Text(
              'Limpar filtros',
              style: DesignTokens.textMonoCaption.copyWith(
                fontSize: 11,
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(ActiveFilterChip chip) => switch (chip) {
    DateRangeChip(option: final option) => _dateRangeLabels[option]!,
    EntryTypeChip(source: final source) => _entryTypeLabels[source]!,
  };
}
