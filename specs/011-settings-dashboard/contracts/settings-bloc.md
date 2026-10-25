# Contract: `SettingsBloc`

`features/settings/presentation/bloc/`. A `get_it` `registerFactory` (screen-scoped, same lifetime pattern as
`RecordsBloc`/`ExportBloc` — a fresh instance per `AppRoutes.settings` visit, never a singleton, since
FR-008/FR-023 require a fresh fetch on every open rather than a resumed prior state).

## Dependencies

`DashboardRepository`, `AccountProfileRepository`, `AccountDeletionRepository`, `AuthRepository`,
`SessionRepository`, `SaveSettingsBiometricPreferenceUseCase`, `VaultRepository` — no `SessionBloc` import
(research.md R11 keeps that cross-bloc touch at the page, not the bloc, same as `RecordsBloc`).

## Events

| Event | Triggers |
|---|---|
| `SettingsOpened` | Dispatched once by the route builder (`app_router.dart`), mirroring `RecordsStarted`. Kicks off: aggregate fetch → (conditionally) narrative fetch; profile load (`SessionRepository`'s cached `Account.email` + `AccountProfileRepository.readCachedDisplayName()` or the email-derived default); biometric capability + current value. |
| `DashboardRetryRequested` | Re-runs the aggregate (and, if it then qualifies, narrative) fetch — FR-007's retry affordance. |
| `NameEditStarted` | `nameEditStatus → editing`, `nameDraft` seeded with the current `displayName`. |
| `NameDraftChanged(String value)` | Updates `nameDraft` only — no validation yet. |
| `NameEditCancelled` | `nameEditStatus → viewing`, `nameDraft` discarded. |
| `NameEditSubmitted` | Validates `nameDraft` first (FR-011); on failure, sets `nameEditFailureMessage`, stays `editing`, **no repository call**. On pass, calls `AccountProfileRepository.updateDisplayName`; on `Right`, `displayName` updates and `nameEditStatus → viewing`; on `Left`, stays `editing` with `nameDraft` intact and a retryable message (FR-012). |
| `BiometricToggleChanged(bool value)` | Optimistically flips `biometricEnabled` (RNF01), calls `SaveSettingsBiometricPreferenceUseCase`; reverts + message on `Left` (contracts/biometric-preference-settings-extension.md). |
| `SignOutRequested` | contracts/account-session-actions.md. |
| `DeleteAccountDialogOpened` / `DeleteAccountDialogCancelled` | Presentation-only — toggles `deleteDialogOpen`; cancel makes **no** backend call (FR-021). |
| `DeleteAccountConfirmed` | contracts/account-deletion-repository.md. |

## `reauthRequired` (research.md R11)

```dart
final _reauthController = StreamController<void>.broadcast();
Stream<void> get reauthRequired => _reauthController.stream;
```
Fired from inside any repository-call handler whenever the result is `Left(AuthExpiredFailure)` *after* that
repository's own single silent-refresh retry has already been exhausted (never for the first attempt, which
retries silently without surfacing anything) — same trigger condition `RecordsBloc`/`ChatSessionsBloc` already
use for their own `reauthRequired` streams. `close()` overridden to also close `_reauthController`, mirroring
`RecordsBloc`.

## `SettingsPage` wiring (`features/settings/presentation/pages/settings_page.dart`)

```dart
late final StreamSubscription<void> _reauthSubscription;

@override
void initState() {
  super.initState();
  _reauthSubscription = context.read<SettingsBloc>().reauthRequired.listen((_) {
    if (!mounted) return;
    context.read<SessionBloc>().add(const AuthExpiredDetected());
  });
}
```
A `BlocListener<SettingsBloc, SettingsState>` with `listenWhen` on `signedOut`/`accountDeleted` becoming
`true` performs `context.go(AppRoutes.login)` — always login, never the vault (research.md R10's correction
note); a second `BlocListener` (or the same one) shows the delete-confirmation `AlertDialog` while
`deleteDialogOpen == true`, closing it automatically on a successful deletion (the destination-change listener
fires in the same frame).

## Session-expiry mid-screen (spec.md Edge Cases; research.md R15)

The existing `main.dart`-level `BlocListener<SessionBloc>` raises the overlay exactly as it does for every
other screen — no change there. Re-authenticating does **not** rebuild `SettingsPage`/`SettingsBloc` (the
reauth `LoginSignupPage` is pushed on top of, then popped back to, the same still-mounted `SettingsPage` —
`showSessionExpiredOverlay`'s own existing mechanism); instead, `SettingsPage`'s `State` is `RouteAware`,
subscribed to the already-existing `chatRouteObserver` (`app_router.dart`):

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  chatRouteObserver.subscribe(this, ModalRoute.of(context)! as PageRoute<void>);
}

@override
void dispose() {
  chatRouteObserver.unsubscribe(this);
  super.dispose();
}

@override
void didPopNext() => context.read<SettingsBloc>().add(const SettingsOpened());
```

So the dashboard, profile, and biometric toggle are "reasonably re-requested" the moment the reauth page above
Settings is popped — matching spec.md's own wording, which is deliberately stronger here than Records'/Chat's
"preserve state, don't necessarily refetch" handling of the same overlay. An in-progress name edit
(`nameEditStatus == editing`, `nameDraft` holding unsaved text) is **not** reset by this `SettingsOpened`
re-dispatch — the handler only refills `dashboardStatus`/`aggregate`/`narrativeStatus`/`biometricEnabled`/
`displayName` (the latter only when not currently being edited), leaving `nameEditStatus`/`nameDraft` alone so
the user's in-progress text survives re-authentication too ("any in-progress edit... not silently lost").
