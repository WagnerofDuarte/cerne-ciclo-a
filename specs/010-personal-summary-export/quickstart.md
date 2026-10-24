# Quickstart: P-RF05 — Personal summary export

How to validate this unit end-to-end once implemented, mapped to spec.md's three user stories. A run guide —
interfaces are in `contracts/`, state/entities in `data-model.md`.

## Prerequisites

- F000, RF01, RF06, RF07 already implemented and passing (this unit depends on RF07's "Meus Registros" screen
  and reuses RF06's `DateRangeOption`/`DateRangeBounds` for the active period, per spec.md's own header).
- `pubspec.yaml` has `share_plus: ^13.3.1` added and `flutter pub get` run (research.md R2) — without it,
  `ExportFileRepositoryImpl` cannot compile.
- A signed-in test account with:
  - at least one entry in "this week" and at least one older than that, to exercise a non-empty
    `DateRangeOption.thisWeek` export distinct from an all-time one;
  - a way to force each of the backend's job-status outcomes for the same account — either a debug/test
    backend toggle, or simply waiting for a real AI-timeout to occur naturally for Story 2's scenario if no
    such toggle exists.
- A second period/account known to have **zero** entries in it, for Story 3.

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html    # RNF07 gate — now covering export_job.dart's
                                                         # sheetState mapping, plus ExportRepositoryImpl's/
                                                         # ExportFileRepositoryImpl's retry/share branches
dart test/architecture/no_bloc_imports_bloc_test.dart   # ExportBloc must not import RecordsBloc or vice versa
dart test/architecture/domain_purity_test.dart          # lib/features/export/domain/** stays Flutter/data-free
```

`contracts/http-client-download-extension.md`, `contracts/export-repository.md`, `contracts/export-bloc.md`,
and `contracts/records-header-export-extension.md` each carry the full scenario table this unit's coverage
depends on.

## Manual verification (device/Simulator)

### Story 1 — Getting a narrative PDF of your entries (P1)

1. On "Meus Registros" with at least one entry in the current filter, tap the download icon (header, top
   right). **Expect**: the sheet opens immediately showing a spinner and "Preparando exportação...".
2. Within a couple of seconds. **Expect**: the sheet transitions on its own, with no tap required, to
   "Gerando resumo com IA..." with a progress bar.
3. Once the backend finishes both the data and the narrative. **Expect**: a green check, "Resumo pronto", and
   two enabled buttons — "Baixar PDF" (filled/primary) and "Baixar dados brutos" (outline).
4. Tap "Baixar PDF". **Expect**: the OS share sheet appears offering a PDF file; completing a save/share
   produces a readable PDF containing a narrative summary of that period's entries.
5. Back in the export sheet, tap "Baixar dados brutos". **Expect**: the OS share sheet appears again, this
   time offering the raw-data file, independent of the PDF download that already happened.
6. Tap "Fechar". **Expect**: the sheet dismisses; "Meus Registros"' list, filters, and scroll position are
   exactly as they were before the download icon was tapped.

### Story 2 — Your raw data is never held hostage by the AI narrative (P1)

1. For a period with entries, force the narrative generation to fail (timeout/error) while the underlying
   data still completes. **Expect**: the sheet shows a red warning, text explaining the AI summary failed but
   the data is still available, and **exactly one** enabled button — "Baixar dados brutos" (no "Baixar PDF").
2. Tap "Baixar dados brutos". **Expect**: it succeeds, independent of the narrative ever having completed.
3. Separately, force the export job to fail entirely (no data produced at all — not just the narrative).
   **Expect**: a *visually and textually distinct* failure state from step 1's — reusing the same red
   warning color/icon family, but different copy, **no** download button of any kind, and only "Fechar"
   available. Confirm the two failure states are clearly distinguishable side by side (take a screenshot of
   each if unsure).
4. From that full-failure state, tap "Fechar", then tap the download icon again. **Expect**: this opens a
   brand-new attempt (Pendente → ...) — not a stuck or repeated failure screen; retrying is "close, then tap
   the download icon again," with no dedicated retry control inside the sheet itself.

### Story 3 — Exporting a period with nothing in it is handled gracefully (P2)

1. Select (via "Meus Registros"' own filter sheet) a period known to have zero entries, then tap the download
   icon. **Expect**: the sheet shows "Nenhum registro nesse período." and a suggestion to adjust the filter
   **immediately** — never a spinner or a progress bar first, even briefly.
2. Confirm no PDF/raw-data download button appears in this state.
3. Tap "Fechar". **Expect**: the sheet dismisses with no file ever having been produced, and "Meus
   Registros"' own list/filters are unaffected.

### Edge cases worth exercising manually at least once

- Tap the download icon, then immediately tap "Fechar" while the sheet still shows "Pendente"/"Processando".
  Reopen the export sheet right after. **Expect**: a brand-new "Pendente" attempt starts — the dismissed
  job's eventual real outcome (if it ever finishes) is simply never shown, and the app is not observed
  polling anything in the background once the first sheet is gone.
- Double-tap the download icon as fast as possible. **Expect**: exactly one sheet opens, exactly one export
  job is created (confirm via backend logs/a debug network inspector if available — no second `POST
  /export/summary` fires).
- Once "Concluído" or the narrative-only "Erro" is showing, tap a download button, then immediately tap it
  again before the first request resolves. **Expect**: only one download/share attempt actually fires; the
  button shows a busy/disabled look in between.
- With the sheet open and showing "Pendente"/"Processando", force the session to expire (e.g. an expired test
  token). **Expect**: the existing "Sessão expirada" overlay appears over the sheet; after re-authenticating,
  the sheet resumes polling and eventually reaches a real terminal state — it never stays stuck on
  "Pendente"/"Processando" forever.
- Once "Concluído" is showing, force the download call to fail after the fact (e.g. simulate the signed URL
  having expired). **Expect**: the tapped button returns to a normal, re-tappable state with no crash and no
  stuck "loading" look; tapping it again retries successfully once the simulated failure is lifted.
