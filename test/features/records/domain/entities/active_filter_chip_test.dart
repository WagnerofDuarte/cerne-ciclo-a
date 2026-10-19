import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/records/domain/entities/active_filter_chip.dart';
import 'package:cerne/features/records/domain/entities/date_range_filter.dart';
import 'package:test/test.dart';

void main() {
  group('ActiveFilterChips.derive', () {
    test('allTime + empty entryTypes -> empty list (no DateRangeChip for the '
        '"no filter" state)', () {
      final chips = ActiveFilterChips.derive(
        dateRange: DateRangeOption.allTime,
        entryTypes: const {},
      );

      expect(chips, isEmpty);
    });

    test('a non-allTime range -> exactly one DateRangeChip', () {
      final chips = ActiveFilterChips.derive(
        dateRange: DateRangeOption.thisWeek,
        entryTypes: const {},
      );

      expect(chips, [const DateRangeChip(DateRangeOption.thisWeek)]);
    });

    test('multiple entryTypes -> one EntryTypeChip per source', () {
      final chips = ActiveFilterChips.derive(
        dateRange: DateRangeOption.allTime,
        entryTypes: {EntrySource.audio, EntrySource.photo},
      );

      expect(chips, hasLength(2));
      expect(chips, containsAll([const EntryTypeChip(EntrySource.audio), const EntryTypeChip(EntrySource.photo)]));
    });

    test('a date range and multiple entry types together -> one chip each', () {
      final chips = ActiveFilterChips.derive(
        dateRange: DateRangeOption.thisMonth,
        entryTypes: {EntrySource.manual, EntrySource.chat},
      );

      expect(chips, hasLength(3));
      expect(chips.first, const DateRangeChip(DateRangeOption.thisMonth));
    });
  });
}
