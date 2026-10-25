# Contract: `AppDrawer`'s display name (research.md R13) — extended in place, no behavior regression

`lib/features/home/presentation/widgets/app_drawer.dart` currently derives both the shown name and the
avatar's initials straight from the email (`_displayNameFromEmail`/`_initialsFromEmail`/`_emailNameWords`),
with a comment naming this unit as the one that wires in a real name. This unit:

1. Deletes `_displayNameFromEmail`/`_initialsFromEmail`/`_emailNameWords` from `app_drawer.dart`.
2. Adds `AccountProfile.defaultDisplayNameFromEmail`/`.initials` (data-model.md) to
   `features/settings/domain/entities/account_profile.dart`, carrying the exact same splitting/title-casing
   behavior forward byte-for-byte (same regex, same join) — not a rewrite, a relocation.
3. `_AppDrawerState` resolves its displayed name as:
   ```dart
   final cached = await getIt<AccountProfileRepository>().readCachedDisplayName();
   final email = await getIt<SecureTokenStorage>().readAccountEmail();
   final displayName = cached ?? (email == null ? null : AccountProfile.defaultDisplayNameFromEmail(email));
   ```
   combined into one `Future<({String? displayName, String? email})>` (or two sequential `FutureBuilder`s —
   implementation detail left to tasks.md) so both pieces resolve before first paint, same as today's single
   `_accountEmail` future. The drawer depends on `AccountProfileRepository` (`settings/domain/`), not on
   `AccountProfileLocalCache` directly — a presentation file reaching into another feature's `data/` class
   directly would be a new, unprecedented cross-feature import shape; going through the domain-layer
   repository interface (already registered as a `get_it` lazy singleton for `SettingsBloc`'s own use) is the
   same "presentation depends on a domain interface, resolved via `get_it`" shape every other cross-feature
   touch in this app already uses.
4. The avatar's `Text` child becomes `AccountProfile(displayName: displayName ?? '?', email: ...).initials`
   instead of the deleted `_initialsFromEmail(email)` call.

## Why this is safe to do here, not deferred

`AccountProfileLocalCache` is a new class this unit already creates (data-model.md); reading it from
`app_drawer.dart` is a presentation→data-layer-via-cache read no different in kind from `SecureTokenStorage`'s
own existing use in the same file — no new architectural seam, just one more secure-storage key read
alongside the one already there. Skipping this step would leave the drawer showing the stand-in email-derived
name forever even after a user successfully renames themselves in Settings — a visible inconsistency between
two screens showing what is supposed to be the same identity, directly contradicted by the comment this unit
is explicitly resolving.

## Test impact

`test/features/home/presentation/` (if any widget test already pumps `AppDrawer` against a fixed email) gains
one more stubbed dependency (`AccountProfileLocalCache.readDisplayName() → null`) to keep its existing
assertions about the email-derived fallback passing unchanged; no existing assertion's *expected value*
changes, since `null` cached ⇒ identical output to today's always-derive-from-email behavior.
