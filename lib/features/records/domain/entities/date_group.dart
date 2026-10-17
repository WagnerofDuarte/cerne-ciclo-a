import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:equatable/equatable.dart';

const _monthNames = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// One date-heading bucket of entries (FR-002). `entries` preserves
/// whatever order the input list already had — `DateGrouper.group` never
/// re-sorts within or across groups.
class DateGroup extends Equatable {
  const DateGroup({required this.label, required this.entries});

  /// "Hoje" | "Ontem" | "{day} de {monthName}" (research.md R9).
  final String label;
  final List<Entry> entries;

  @override
  List<Object?> get props => [label, entries];
}

/// Buckets an already newest-to-oldest-sorted entry list by calendar day
/// (data-model.md). Only buckets — never sorts.
class DateGrouper {
  const DateGrouper._();

  static List<DateGroup> group(List<Entry> entries, {DateTime? now}) {
    final today = (now ?? DateTime.now()).toLocal();
    final groups = <DateGroup>[];

    DateTime? currentDay;
    List<Entry> currentEntries = [];

    void flush() {
      final day = currentDay;
      if (day != null) {
        groups.add(DateGroup(label: _labelFor(day, today), entries: currentEntries));
      }
    }

    for (final entry in entries) {
      final occurredAt = entry.occurredAt.toLocal();
      final day = DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
      if (day != currentDay) {
        flush();
        currentDay = day;
        currentEntries = [];
      }
      currentEntries.add(entry);
    }
    flush();

    return groups;
  }

  static String _labelFor(DateTime day, DateTime today) {
    final todayDay = DateTime(today.year, today.month, today.day);
    final difference = todayDay.difference(day).inDays;

    if (difference == 0) return 'Hoje';
    if (difference == 1) return 'Ontem';
    return '${day.day} de ${_monthNames[day.month - 1]}';
  }
}
