# Contract: Filter sheet & active-filter UI (`lib/features/records/presentation/widgets/`)

UI-only contract (no new domain/bloc surface beyond what `records-bloc-extension.md` already defines) —
mapping prototype-extract.md §2.4's three "Tela 4" states (Sheet de filtro / Filtros ativos / the funnel
button's filled state on the default "Meus Registros" view) to concrete widgets.

## `FilterSheet` (`filter_sheet.dart`) — NEW

Opened via `showModalBottomSheet` from `records_page.dart`'s funnel `IconButton`, seeded with the
`RecordsBloc`'s *current* `RecordsLoaded.dateRange`/`.entryTypes` (so re-opening the sheet shows what's
already applied, not a reset form):

```dart
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initialDateRange, required this.initialEntryTypes});
  final DateRangeOption initialDateRange;
  final Set<EntrySource> initialEntryTypes;
}

class _FilterSheetState extends State<FilterSheet> {
  late DateRangeOption _dateRange = widget.initialDateRange;
  late Set<EntrySource> _entryTypes = {...widget.initialEntryTypes};
  final Set<_CategoryChip> _categoryChips = {};   // local-only, never read outside this widget (FR-004)
}
```

- **"INTERVALO DE DATA"** — single-choice chip group over `DateRangeOption.values`, labels from
  data-model.md's mapping table ("Todo o período" / "Esta semana" / "Este mês"); selecting one replaces
  `_dateRange` (radio semantics, matches prototype-extract.md's "single choice").
- **"CATEGORIA"** — multi-select chip group over a presentation-only enum (English identifiers per
  Constitution Principle IV, with a local label map for the Portuguese chip text — same pattern
  `DateRangeOption` already uses):
  ```dart
  enum _CategoryChip { work, routine, rest, relationships }
  // label map (local to filter_sheet.dart): work → "trabalho", routine → "rotina",
  // rest → "descanso", relationships → "relações"
  ```
  Tapping toggles membership in `_categoryChips`. This enum and set exist **only** inside `filter_sheet.dart`
  — no field of this name exists anywhere in `RecordsEvent`/`RecordsState`/`EntriesRepository` (FR-004;
  reconfirmed in plan.md's Post-Design Constitution Check).
- **"TIPO DE ENTRADA"** — multi-select chip group over `EntrySource.values`, toggling membership in
  `_entryTypes`.
- **"Aplicar"** — `Navigator.pop(context)` carrying `(dateRange: _dateRange, entryTypes: _entryTypes)` back to
  the caller (`records_page.dart`), which dispatches `FilterSheetApplied(dateRange: ..., entryTypes: ...)` to
  `RecordsBloc`. `_categoryChips` is discarded here — never read, never sent (FR-004).
- **"Limpar"** — local-only `setState`: `_dateRange = DateRangeOption.allTime; _entryTypes = {};
  _categoryChips = {};`. Does **not** close the sheet and does **not** dispatch anything (Story 2/Acceptance
  Scenario 3: "every selection in the sheet resets before it is applied" — the user still taps "Aplicar"
  afterward to commit the now-cleared selection, or dismisses the sheet to abandon the change entirely).

## `ActiveFilterChipsRow` (`active_filter_chips_row.dart`) — NEW

Rendered directly under `_SearchBar` in `records_page.dart`, only when `RecordsLoaded.activeChips.isNotEmpty`
(FR-006):

```dart
class ActiveFilterChipsRow extends StatelessWidget {
  const ActiveFilterChipsRow({super.key, required this.chips});
  final List<ActiveFilterChip> chips;
}
```

- One removable `Chip`/`InputChip` per entry in `chips`:
  - `DateRangeChip(option)` → label from data-model.md's mapping table.
  - `EntryTypeChip(source)` → label = the prototype's own entry-type labels ("manual" / "áudio" / "foto" /
    "chat" — prototype-extract.md §2.4's "TIPO DE ENTRADA" chip names).
  - Each chip's delete/close icon dispatches `FilterChipRemoved(chip)`.
- A trailing "Limpar filtros" `TextButton` dispatching `FiltersAndSearchCleared` (FR-006/FR-007) — clears
  **both** the Filter Set and any active search text, even though the search text itself has no chip of its
  own (data-model.md's `ActiveFilterChips.derive()` note).

## Funnel button filled state (`records_page.dart`'s `_SearchBar`, extended)

```dart
IconButton(
  onPressed: () => _openFilterSheet(context),
  icon: Icon(
    Icons.filter_alt,                                           // filled variant
    color: hasActiveFilters ? DesignTokens.colorOnAccent : DesignTokens.colorTextPrimary,
  ),
  style: IconButton.styleFrom(
    backgroundColor: hasActiveFilters ? DesignTokens.colorAccent : DesignTokens.colorSurfaceElevated,
    side: const BorderSide(color: DesignTokens.colorBorder),
    shape: const CircleBorder(),
    fixedSize: const Size(40, 40),
  ),
)
```

`hasActiveFilters` reads `RecordsLoaded.hasActiveFilters` (Filter Set only — date range + entry types, not the
search text, matching FR-006's own scoping) — swapping `Icons.filter_alt_outlined`/neutral styling (RF07's
original inert rendering) for the filled variant above whenever true.

## Search bar made live (`records_page.dart`'s `_SearchBar`, extended)

```dart
TextField(
  enabled: true,                                                  // was `false` (RF07/FR-008)
  onChanged: (text) => context.read<RecordsBloc>().add(SearchTextChanged(text)),
  decoration: const InputDecoration(/* unchanged from RF07 */),
)
```

No local debounce logic in the widget — `SearchTextChanged` is dispatched on every keystroke; the debounce
lives entirely inside `RecordsBloc` (research.md R4).

## `NoResultsForCriteriaView` (`no_results_for_criteria_view.dart`) — NEW

```dart
class NoResultsForCriteriaView extends StatelessWidget {
  const NoResultsForCriteriaView({super.key, required this.onAdjustPressed});
  final VoidCallback onAdjustPressed;
}
```

Distinct message/icon from `records_empty_state.dart` (FR-009) — "Nenhum resultado para esta busca/filtro" (or
equivalent prototype-faithful copy) plus a button calling `onAdjustPressed`, wired in `records_page.dart` to
`context.read<RecordsBloc>().add(const FiltersAndSearchCleared())`.

## Test scenarios this contract owns (for `/speckit-tasks` to schedule)

| # | Scenario | Expected |
|---|---|---|
| 1 | Open `FilterSheet` with no prior criteria, select "Esta semana" + "áudio", tap "Aplicar" | sheet closes; `RecordsBloc` receives `FilterSheetApplied(dateRange: thisWeek, entryTypes: {audio})` |
| 2 | Open `FilterSheet` with `{audio, photo}` already applied | both chips render pre-selected (the sheet reflects current state, not a blank form) |
| 3 | Inside the sheet, select a "CATEGORIA" chip, tap "Aplicar" | the dispatched `FilterSheetApplied` carries no category information at all |
| 4 | Inside the sheet, select several chips, tap "Limpar" | all local chip selections visually clear; sheet stays open; nothing is dispatched |
| 5 | `RecordsLoaded.hasActiveFilters == true` | funnel button renders filled (`colorAccent` background) |
| 6 | `RecordsLoaded.activeChips` has 2 entries | `ActiveFilterChipsRow` renders 2 removable chips + "Limpar filtros" |
| 7 | Tap a chip's remove control | dispatches `FilterChipRemoved` with that exact chip value |
| 8 | Tap "Limpar filtros" | dispatches `FiltersAndSearchCleared` |
| 9 | `isEmptyForCriteria == true` | `NoResultsForCriteriaView` renders, not `RecordsEmptyState` |
| 10 | Type into the search bar | `SearchTextChanged` dispatched once per keystroke (debounce coalescing verified in `records-bloc-extension.md`'s own tests, not here) |
