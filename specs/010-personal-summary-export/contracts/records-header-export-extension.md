# Contract: Records header's download icon (`lib/features/records/presentation/pages/records_page.dart`)

Extends `_Header`/`_RecordsPageState` in place (FR-001/FR-002/FR-011). `RecordsBloc`/`RecordsEvent`/
`RecordsState` are unchanged — no new event, no new field (research.md R8).

```dart
class _Header extends StatelessWidget {
  const _Header({required this.onExportPressed});
  final VoidCallback onExportPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ...unchanged back-arrow + title...
      child: Row(
        children: [
          /* back arrow, title — unchanged */
          IconButton(
            onPressed: onExportPressed,                              // was: () {} (inert placeholder)
            icon: const Icon(Icons.download_outlined, color: DesignTokens.colorTextPrimary),
          ),
        ],
      ),
    );
  }
}
```

```dart
class _RecordsPageState extends State<RecordsPage> {
  bool _isOpeningExportSheet = false;   // NEW

  Future<void> _openExportSheet(BuildContext context) async {
    if (_isOpeningExportSheet) return;                                   // FR-011
    _isOpeningExportSheet = true;
    final state = context.read<RecordsBloc>().state;
    final dateRange = state is RecordsLoaded ? state.dateRange : DateRangeOption.allTime;
    final bounds = dateRange.boundsAt(DateTime.now());                    // RF06's own pure extension, reused
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExportSheet(periodStart: bounds.from, periodEnd: bounds.to),
    );
    if (mounted) _isOpeningExportSheet = false;
  }

  // build(): `_Header(onExportPressed: () => _openExportSheet(context))` replaces the bare `_Header()`.
}
```

- `_isOpeningExportSheet` resets to `false` only after `showModalBottomSheet`'s `Future` resolves (the sheet
  was dismissed) and only if the widget is still mounted — a second tap while the sheet is open is already
  physically blocked by the modal barrier Flutter itself draws, so this flag's only real job is absorbing a
  double-tap in the brief window before the sheet has finished animating in.
- No change to `RecordsBloc`'s own filter state: reading `context.read<RecordsBloc>().state` here is a
  one-time snapshot at tap time, never a `watch` — `_Header` itself stays a plain, non-rebuilding
  `StatelessWidget` with respect to `RecordsBloc` (unaffected by RF05, same as `_SearchBar`'s existing
  `context.watch<RecordsBloc>()` usage for the filter icon's own highlight state, which this unit does not
  touch).

## Test scenarios this contract owns

| # | Scenario | Expected |
|---|---|---|
| 1 | `RecordsLoaded(dateRange: DateRangeOption.thisWeek)`, download icon tapped | `ExportSheet` is constructed with `periodStart` = this week's most-recent-Monday boundary, `periodEnd: null` |
| 2 | `RecordsLoaded(dateRange: DateRangeOption.allTime)`, download icon tapped | `ExportSheet` is constructed with `periodStart: null, periodEnd: null` |
| 3 | Download icon tapped twice in rapid succession (before the first `showModalBottomSheet` future resolves) | `showModalBottomSheet` is called exactly once |
| 4 | Sheet dismissed, download icon tapped again | `showModalBottomSheet` is called again (a fresh `ExportSheet`/`ExportBloc`, research.md R6) — not blocked by the now-`false` guard |
| 5 | Opening/closing the export sheet, at any of its states | `RecordsBloc`'s own state (`entries`, `dateRange`, scroll position via `ScrollController`) is bit-for-bit unchanged before and after (FR-010/SC-004) |
