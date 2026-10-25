# Research: P-RF09 — Temporal summaries / dashboard

Phase 0 output. Each item is a technical-judgment decision this plan must make beyond what spec.md's own FRs/
Clarifications/Assumptions already resolve (Constitution Principle I: "where these documents are silent,
implementers MUST make a reasonable technical decision rather than block on clarification"). None of these
reopen a resolved Clarification; each builds directly on spec.md's own wording.

## R1 — Dashboard data flow is two independent repository calls, gated by `totals.count`

`DashboardRepository.fetchAggregate()` and `fetchNarrative()` are two separate methods, called separately by
`SettingsBloc`, never composed into one. The aggregate call always fires on `SettingsOpened`/retry (FR-001,
FR-008). The narrative call fires only after the aggregate succeeds **and** `aggregate.totals.count >= 2`
(FR-003/FR-004/FR-005) — the bloc inspects the already-resolved aggregate's own total, never a second network
round-trip to "find out" the count. Both calls send the single fixed query parameter `period=all` (spec.md
Assumption "Dashboard period") — no period parameter is ever user-controlled in this unit.

## R2 — Ten-bar bucketing is a pure, total function over `(buckets, today)`

Spec.md's Clarification/Assumption fixes the algorithm in words ("divide the account's full date range — date
of the first entry through today — into ten roughly-equal time slices and sum the per-date counts falling
within each slice"); this unit only has to fix the exact integer arithmetic so the function is deterministic
and testable:

```
List<int> tenBars(List<AggregateBucket> buckets, DateTime today) {
  if (buckets.isEmpty) return List.filled(10, 0);
  final start = buckets.map((b) => b.date).reduce((a, b) => a.isBefore(b) ? a : b);
  final totalDaySpan = today.difference(start).inDays; // >= 0; both date-only (UTC midnight)
  final bars = List.filled(10, 0);
  if (totalDaySpan == 0) {
    // Every entry happened "today" relative to the account's own first entry
    // (e.g. 2 entries created minutes apart) — a single-day range cannot be
    // divided into 10 meaningful slices, so the whole total lands in the
    // last bar rather than every bar collapsing onto index 0.
    bars[9] = buckets.fold(0, (sum, b) => sum + b.count);
    return bars;
  }
  for (final bucket in buckets) {
    final daysSinceStart = bucket.date.difference(start).inDays;
    final index = (daysSinceStart * 10) ~/ (totalDaySpan + 1);
    bars[index.clamp(0, 9)] += bucket.count;
  }
  return bars;
}
```
`totalDaySpan + 1` (not `totalDaySpan`) is the slice divisor so the very last day (`daysSinceStart ==
totalDaySpan`) still lands inside bar index 9, not spilling past it. This function is pure (no `DateTime.now()`
inside it — the caller passes `today`), lives in `domain/`, and is the one piece of this unit's logic RNF07
most needs to hit ≥80% on, mirroring `DateRangeFilter`/`SyncBadgeState`'s existing pure-derivation shape.

## R3 — No new charting dependency

The chart is always exactly 10 bars with no interaction (no tooltip, no zoom, no legend) — a `Row` of 10
`Container`s whose heights are `count / maxBarCount * DesignTokens.sizeChartBarMaxHeight` (clamped to a
minimum visible sliver for a non-zero, sub-pixel bar) already renders this losslessly with widgets the app
already depends on. Adding `fl_chart`/`syncfusion_flutter_charts`/etc. for 10 static bars would be the first
charting dependency in the app for a shape plain `Flutter` already draws — rejected (Complexity Tracking).
Principle II's "chart package" being a free/open choice means "free to add one if needed," not "must add one."

## R4 — `SettingsState` is one flat composite state, not a sealed per-mode hierarchy

Unlike `VaultBloc` (a strictly sequential state machine — PIN setup, then biometric prompt, then unlock) or
`ExportBloc` (one sheet, one job, mutually exclusive terminal states), Settings' four concerns — dashboard,
narrative, profile/name-edit, biometric toggle, sign-out, account-deletion — load and update **independently**
of one another on the same screen at the same time (e.g. the name can be mid-edit while the dashboard is still
loading). `SettingsState` is therefore one `Equatable` class with a field per concern and a `copyWith` using
the same `_unset` sentinel pattern `RecordsLoaded` already establishes for nullable fields that must be
explicitly clearable — the same shape, scaled to more independent regions, not a new pattern.

## R5 — Display-name caching: new, settings-owned local cache; biometric state: no new cache at all

Spec.md's "Account Profile" Key Entity requires treating "the most recent successful write... as the locally
held source of truth," including biometricEnabled, "defaulting sensibly... for an account that has never had
a successful write." Splitting this per field is simpler and more correct than a single shared cache:

- **`displayName`** has no on-device mirror anywhere else in the app — RF03 never writes it. A new
  `AccountProfileLocalCache` (`features/settings/data/`, Keychain-backed via `flutter_secure_storage`, same
  pattern as `VaultSecureStorage`/`EntriesLocalCache`) persists only the name this unit's own successful
  `PATCH` last confirmed. `AccountProfile.defaultDisplayNameFromEmail(email)` (see R13) supplies the sensible
  default when the cache is empty.
- **`biometricEnabled`** already has an authoritative, always-correct on-device mirror:
  `VaultRepository.isBiometricPreferenceEnabled()` (`VaultSecureStorage`), written synchronously during RF03's
  first-time setup regardless of whether that setup's own backend write succeeded (RF03 FR-014, local-first).
  Reading the toggle's initial state from there is *more* correct than inventing a second, settings-owned
  cache that RF03's write path would have to be taught to also populate — it is already "the most recent
  successful write" in the sense that matters (what the device itself currently enforces). No vault file needs
  to change for this unit to read it.

## R6 — Settings' own biometric-toggle write path: await + revert, reusing RF03's repository as-is

FR-014 ("the toggle MUST revert... rather than appearing to succeed") is the opposite contract from RF03's
existing `SaveBiometricsPreferenceUseCase` (`vault/domain/usecases/`), which is deliberately fire-and-forget
("always completes regardless of outcome" — RF03 research.md R6, first-time setup must never block on the
network). Rather than changing that usecase's contract (and risking RF03's own already-shipped behavior), this
unit adds a new, settings-owned usecase, `SaveSettingsBiometricPreferenceUseCase`
(`features/settings/domain/usecases/`), that:
1. calls `BiometricsPreferenceRepository.save(enabled)` (vault's existing, single-field repository — reused
   verbatim, not re-implemented — "continuing the account-settings read/write path RF03 already established
   for this same flag," FR-013's own wording) and *awaits* the `Either`;
2. on `Right`: calls `VaultRepository.setBiometricPreferenceLocally(enabled)` so the device's own unlock gate
   and Settings' displayed value move together;
3. on `Left`: returns the failure untouched — the local mirror is never written, so a later app relock still
   gates on the last-confirmed value, and `SettingsBloc` reverts the toggle's optimistic UI flip.

`BiometricsPreferenceRepository`/`BiometricsPreferenceRemoteDataSource` (vault/) are unmodified; this is a new
caller, not a new implementation.

## R7 — Display-name write path: new, narrow `AccountProfileRepository`

Mirrors `BiometricsPreferenceRepository`'s own documented reasoning ("deliberately narrow... rather than a
general-purpose account-settings repository"). A new `AccountSettingsRemoteDataSource.updateDisplayName()`
(`features/settings/data/`) sends `PATCH account-settings-update` with `{"displayName": ...}` only (never
`persona`, FR-015). `AccountProfileRepositoryImpl.updateDisplayName()` persists the confirmed name into
`AccountProfileLocalCache` before returning `Right` (FR-010, SC-005), and never touches `biometricEnabled` or
`persona` — a client-side-only `AccountProfile` validation (1–80 chars, FR-011) runs in the bloc before any
repository call, so an invalid name never reaches the network.

## R8 — Logout extends the existing `auth/` feature; account deletion is new, inside `settings/`

`POST /auth/logout` (`auth-logout`) is an auth-domain concern indistinguishable in shape from
`auth-signup`/`auth-login`, already owned by `AuthRepository`/`AuthRemoteDataSource`/`AuthRepositoryImpl`
(`features/auth/`) — this unit adds one method, `logout()`, to all three, the same "extend an earlier unit's
file in place" precedent RF05 already set on `records_page.dart`. `DELETE /account` (`account-delete`) is new
and squarely RF09/RNF05-owned, so it gets its own repository inside `features/settings/`
(`AccountDeletionRepository`/`AccountDeletionRemoteDataSource`/`AccountDeletionRepositoryImpl`), sending the
backend-required `{"confirmation": "DELETE"}` body the user never types (FR-018).

## R9 — What gets cleared locally: logout is narrower than account deletion, by FR text

FR-016 (Sair): "clear the local session and any cached account/profile state." FR-019 (Apagar conta): "clear
all local session, cached account/profile, **and any other locally held user data**." The extra clause in
FR-019 is read literally as a scope difference, not a wording accident — deleting the account is the LGPD hard
-delete path and must leave nothing recoverable; logging out from an account that still exists has no such
requirement. Concretely:

- **Both** actions clear `SessionRepository` (`SecureTokenStorage`'s 4 keys) and `AccountProfileLocalCache`
  (the cached display name) — the two "session" and "cached account/profile" nouns FR-016 itself names.
- **Only account deletion** additionally clears `EntriesLocalCache`/`ChatLocalCache` (both extended in place
  with a new `clear()` method, R14) and their owning repositories' in-memory mirrors (`EntriesRepository`/
  `ChatRepository` gain a `clearLocalData()` method each) — "any other locally held user data," FR-019.
- **Neither** action touches `VaultSecureStorage` (the device PIN hash or the biometrics-preference mirror) —
  see R10, this is deliberate and matches the prototype's own simulated destination.

## R10 — Post-logout/deletion destination: computed from `hasPinConfigured()`, reusing existing routes only

The prototype extract states both "Sair" and "Apagar tudo" return to "Tela 0.1 — Biometria" — the same
destination (`prototype-extract.md` §1, §4.2). Spec.md's own Assumption resolves "the app's authentication
entry point" as "whatever F000/RF03 already resolve that case to (the vault screen if a device-level
PIN/biometric flow applies with no session, falling through to login otherwise) rather than building a
separate destination." The literal, minimal reading of that: `SettingsBloc` checks
`VaultRepository.hasPinConfigured()` after the session/profile clear and resolves to `AppRoutes.vault` (if
true) or `AppRoutes.login` (if false) — the same two routes `SplashPage` already builds its own routing
decision from, never a new route or screen. `SettingsPage` performs `context.go()` (not `push`) on the
resulting terminal state, discarding the whole Home/Settings back-stack, so there is no way to navigate back
into a signed-out Settings screen. Whatever happens *after* a vault unlock with no stored session (i.e.
arriving at Home with nothing to authenticate it) is explicitly left to the already-existing, already-built
expired-session machinery named in spec.md's own Edge Cases ("the existing expired-session handling —
established by F000, continued by RF07 — takes over exactly as it does elsewhere") — this unit does not add a
second mechanism for that.

> **Superseded (PRD correction, device QA on sign-out).** The "whatever happens after a vault unlock with no
> stored session" assumption above does not hold: `VaultPage`'s unlock success (`VaultMode.gatekeeper`)
> unconditionally does `context.go(AppRoutes.home)` with no session check, and nothing on `Home` proactively
> re-validates the session either — the existing expired-session machinery only fires reactively, off a failed
> API call. On a physical device with the biometric toggle on, this meant "Sair" re-triggered Face ID and, on
> success, landed on an authenticated-looking but session-less Home. Corrected behavior: both `signedOut` and
> `accountDeleted` now resolve unconditionally to `AppRoutes.login`, never `AppRoutes.vault` —
> `hasPinConfigured()` is no longer consulted for either action, and `SettingsState`'s
> `SettingsDestination`/`signedOutDestination`/`accountDeletedDestination` are replaced with plain
> `signedOut`/`accountDeleted` booleans (there being only one possible destination left). The vault screen
> remains reachable only from app-relaunch/relock, where a live session actually exists for it to gate.

## R11 — Reauth wiring reuses the established `reauthRequired` stream pattern

`SettingsBloc` exposes a broadcast `Stream<void> get reauthRequired`, fired whenever a repository call's single
silent-refresh retry (the same `_retryAfterSilentRefresh` shape `EntriesRepositoryImpl`/`ChatRepositoryImpl`
already use) still comes back `AuthExpiredFailure`. `SettingsPage` subscribes in `initState` and forwards to
`context.read<SessionBloc>().add(const AuthExpiredDetected())` — verbatim the same wiring `RecordsPage`/
`AppDrawer`/`ExportSheet` already each do for their own blocs (research.md precedent, RF06/RF07/RF05). The
already-wired, app-level `BlocListener<SessionBloc>` in `main.dart` is what actually raises the overlay; this
unit adds no second overlay-raising mechanism.

## R12 — Double-tap guards are in-flight booleans on `SettingsState`, not a separate mechanism

FR-022 is satisfied the same way `ExportBloc`'s own tap-guard already is: `isSigningOut`/`isDeletingAccount`
booleans on `SettingsState`, checked at the top of the corresponding event handler before any repository call
is made — a second tap while one is `true` is a no-op. No new synchronization primitive, no shared mutable
flag outside the bloc's own state.

## R13 — `AccountProfile`'s email-derived default is extracted from `AppDrawer`, not duplicated

`app_drawer.dart`'s `_displayNameFromEmail`/`_initialsFromEmail`/`_emailNameWords` (private, email-local-part
-splitting functions) carry their own comment: *"A real display name belongs to the Configurações unit... this
is a stand-in until that unit wires one in."* This unit is that unit. The three functions move, unchanged in
behavior, into `features/settings/domain/entities/account_profile.dart` as `AccountProfile`'s static
`defaultDisplayNameFromEmail(email)` and an `initials` getter (now deriving initials from whatever
`displayName` is actually showing — the cached/edited name once one exists, the email-derived default
otherwise — rather than always re-deriving from the email). `AppDrawer` is extended in place to read
`AccountProfileRepository.readCachedDisplayName()` (`settings/domain/`, falling back to the same default)
instead of always showing the email-derived stand-in, and to call the shared `AccountProfile.initials` instead
of its own now-deleted private copies — the drawer and Settings show the same name from the same source, by
construction. This is a genuinely cross-feature domain import (`features/home/presentation/` →
`features/settings/domain/`), the same shape `ChatBloc`'s import of
`entries/domain/usecases/create_entry_usecase.dart` already establishes as acceptable under Principle V —
never a reach into `settings/data/`'s `AccountProfileLocalCache` directly.

## R14 — New design tokens: avatar size + chart geometry only; colors fully reused

`DesignTokens`' panel has no numeric bar-chart dimensions and no 52px avatar size (only `sizeAvatarMenu = 40`).
Four new, narrowly-scoped size tokens are added — `sizeAvatarSettings` (52, prototype-extract.md §6's own
"52px in Configurações"), `sizeChartBarMaxHeight`, `sizeChartBarWidth`, `sizeChartBarGap` — plus one new color,
`colorChartPlaceholder`, for the "light-gray placeholder chart icon" the zero-entries state needs (no existing
token is documented as light-gray; `colorBorder` (`#E1DACB`) is the closest existing neutral and is reused as
this new token's value rather than inventing an unrelated hex, keeping the palette internally consistent). The
"ochre" bar color is `DesignTokens.colorAccent` verbatim — already documented in the tokens panel and already
used for exactly this "CTA, insight, saved bookmark" register; the "10-bar ochre chart" wording in
prototype-extract.md §2.6 names the existing accent color, not a new one.

## R15 — Post-reauth refresh on Settings: `RouteAware`, reusing the existing `chatRouteObserver`

Spec.md's Edge Case for Settings explicitly differs from Records'/Chat's own expired-session handling: "the
dashboard, profile, and any in-progress edit [are] reasonably re-requested, not silently lost" — "re-requested"
is a stronger guarantee than Records' own (which only promises no lost scroll position, not a refetch).
Because `showSessionExpiredOverlay` pushes the reauth `LoginSignupPage` via `rootNavigatorKey` — the exact
`Navigator` `GoRouter` itself renders into (`app_router.dart`'s own `navigatorKey: rootNavigatorKey`) — and
`context.push(AppRoutes.settings)` (how `AppDrawer` already reaches Settings) stacks `SettingsPage` on that
same navigator, the already-registered `chatRouteObserver` (`app_router.dart`, currently subscribed to only by
`HomeChatShellPage` to detect being covered) observes a Settings-covering reauth push/pop too. `SettingsPage`'s
`State` becomes `RouteAware`, subscribes to the same `chatRouteObserver` instance in `didChangeDependencies()`
(mirroring `HomeChatShellPage`'s own subscribe/unsubscribe shape exactly), and dispatches a fresh
`SettingsOpened` from `didPopNext()` — the moment the reauth page above it is popped and Settings becomes the
topmost route again. This is a second subscriber to an existing, already-general-purpose `RouteObserver`, not
a second observer registered on `GoRouter` itself.

## R16 — RNF09's project-wide write-endpoint tally: this unit's contribution, not a final count

Every prior unit's plan reports its own new write-endpoint coverage without asserting the project-wide
fraction's exact final value (009's research.md R13 explicitly declines to, for the same reason — later units'
own contributions aren't yet verifiable from an earlier plan). This unit adds full timeout/malformed/
no-connection coverage for two **new** write endpoints — `account-delete` (`DELETE`, contracts/
account-deletion-repository.md) and `auth-logout` (`POST`, empty body, contracts/account-session-actions.md)
— and extends `account-settings-update`'s existing coverage (already contributed by RF03) with a second,
independently-sent field (`displayName`, contracts/account-profile-repository.md). `dashboard-aggregate-get`/
`dashboard-narrative-get` are `GET`s, outside RNF09's "write endpoint" tally, but are still fully
`Either`-typed and covered by contracts/dashboard-repository.md's own scenario table regardless, same as every
prior unit's read endpoints.
