# Research: P-F000 — Foundation

Every item below was a "NEEDS CLARIFICATION" or a constitution-flagged "free" choice (routing, HTTP
client, local cache, DI, secure storage, biometrics, charting). Biometrics and charting are not
exercised by F000, so they are left open for the units that need them (RF03, RF09).

## R1 — Flutter/Dart version to pin via `fvm`

- **Decision**: Pin this project to Flutter `3.47.5` / Dart `3.13.4`, stable channel.
- **Rationale**: The constitution fixes "Flutter and Dart at the version pinned via `fvm`" but no
  `.fvmrc` exists yet in this repo — F000 is where the pin is created. `fvm list` on this machine
  already shows `3.47.5`/stable cached as the global default (released 2026-09-18), avoiding a
  fresh multi-GB download and giving a reproducible, already-verified SDK.
- **Alternatives considered**: Pinning an older LTS-style version — rejected, no such version is
  already available locally and the constitution expresses no preference for anything but
  "the version pinned via fvm," which this satisfies directly.

## R2 — HTTP client

- **Decision**: `dio`.
- **Rationale**: FR-003/FR-004 require one call surface that always yields `Either<Failure, T>`
  and uniformly translates `{code, message, retryable, requestId}` into a typed failure; Principle
  III requires injecting `apikey` and the right `Authorization` value per call. `dio`'s
  `Interceptor` API is the natural place to inject both headers once and to centralize
  timeout/malformed/offline detection for every later unit's write endpoints (RNF09), rather than
  repeating that logic per repository.
- **Alternatives considered**: `package:http` — would need a hand-rolled interceptor-equivalent
  layer for header injection and timeout classification, duplicating what `dio` gives for free;
  rejected as unnecessary extra surface for no benefit given `dio` is already the de-facto standard
  paired with `flutter_bloc` + `fpdart` repositories.

## R3 — Routing and the two "overlay" requirements (side menu, Sessão expirada)

- **Decision**: `go_router` for top-level screen navigation, with a single root `Navigator` stack
  (`context.push`, not `go`/`replace`, from the side menu). The side menu itself is a plain
  `Scaffold.drawer` (`Drawer` widget), not a route. The "Sessão expirada" overlay is a
  non-dismissible `showDialog` raised through a root `navigatorKey` whenever `SessionBloc` observes
  an `AUTH_EXPIRED` failure that silent refresh could not resolve.
- **Rationale**: FR-013/FR-014 and User Story 5 require the screen underneath the overlay to keep
  its exact state (e.g., scroll position). Flutter never disposes a `State` object that is merely
  covered by a drawer or by a dialog route pushed on top of it — only `push`ing (not `go`/replacing)
  guarantees this for screen-to-screen navigation too (FR-011, User Story 4: "returning to
  Home/Chat, confirming Home/Chat's state unchanged"). This reaches both behaviors without a
  nested/branch-navigation scheme.
- **Alternatives considered**: `StatefulShellRoute` (go_router's persistent-tab branches) — gives
  the same state-preservation guarantee but is built for bottom-nav-style parallel branches; Meus
  Registros/Configurações are occasional side-menu destinations, not a tab bar, so plain stack
  `push` is the simpler fit. A hand-built `Overlay`/`OverlayEntry` for the expired-session case was
  considered instead of `showDialog` — rejected: `showDialog` already is an overlay route with a
  scrim, matching the prototype's "centered card over a light scrim" description with less custom
  code.

## R4 — Dependency injection / service location

- **Decision**: `get_it`, with manual registration (no code generation).
- **Rationale**: F000 only wires a handful of singletons (`ApiClient`, `SecureTokenStorage`, two
  repositories, two blocs-as-factories). `get_it` is the standard pairing with `flutter_bloc` for
  exposing repositories/use cases to `BlocProvider`s without threading them through constructors
  manually, and manual registration avoids adding a build-time code-gen dependency for a graph this
  small.
- **Alternatives considered**: `injectable` (codegen over `get_it`) — rejected for now as
  premature; the registration list is small enough that generated code would add build complexity
  without a proportional benefit. Can be introduced later without touching domain code if the
  graph grows.

## R5 — On-device secure storage for tokens

- **Decision**: `flutter_secure_storage`.
- **Rationale**: Assumptions in spec.md require access/refresh tokens to survive app restarts; the
  app ships iOS-only, where `flutter_secure_storage` backs onto the Keychain — appropriate for
  credentials, unlike unencrypted `shared_preferences`.
- **Alternatives considered**: `shared_preferences` — rejected, stores in plaintext and is
  unsuitable for refresh tokens even on a single-platform (iOS) app.

## R6 — Error/Failure mapping scope

- **Decision**: `core/network/failure.dart` models all 13 closed error codes from
  `docs/input/backend/error-taxonomy.md` now, even though F000's own 4 endpoints can only return a
  subset of them.
- **Rationale**: FR-004 says the system must translate "every backend error response['s] error
  code" — worded generically, not scoped to F000's own calls — and this file is exactly the shared
  piece "no single requirement owns but all of them use" that requirements.md §12 assigns to F000.
  Defining it once now means RF01–RF09 never need to touch this file, only add usages of it.
- **Alternatives considered**: Mapping only the codes F000's endpoints can return (`AUTH_EXPIRED`,
  `AUTH_INVALID`, `NETWORK_TIMEOUT`, `NETWORK_OFFLINE`, `VALIDATION_ERROR`, `RATE_LIMITED`) and
  letting later units extend the hierarchy — rejected: the taxonomy is explicitly closed and fully
  known today, so extending it later would be a pure mechanical addition with no new information,
  while leaving it incomplete risks a later unit quietly handling an "unknown" code path instead of
  its real typed `Failure`.

## R7 — Splash-time session check under a network failure

- **Decision**: If `GET auth-session` (or the subsequent `POST auth-refresh` fallback) itself fails
  with `NETWORK_TIMEOUT` or `NETWORK_OFFLINE` — as opposed to resolving to `AUTH_EXPIRED`/
  `AUTH_INVALID` — the splash screen shows its connectivity-aware state with a manual retry action,
  rather than routing straight to the login screen.
- **Rationale**: Spec.md's edge cases and FR-010 require the splash to never leave the user "stuck"
  and User Story 3 only specifies the valid/expired-renewable/none outcomes — a transient network
  failure is a fourth, unspecified case. Routing straight to login would be actively wrong for a
  user who does have a valid stored session but is momentarily offline; silently retrying forever
  would leave them stuck. A visible retry affordance satisfies "never stuck" without discarding a
  potentially-valid session. This is the reasonable technical decision Constitution Principle I
  calls for where the inputs are silent.
- **Alternatives considered**: Auto-retry with exponential backoff and no user action — rejected,
  can still leave the user staring at the splash indefinitely on sustained offline, which the spec's
  edge cases explicitly want to avoid.

## R8 — iOS minimum deployment target

- **Decision**: Leave it at whatever `flutter create` generates for the pinned 3.47.5 SDK; do not
  override it.
- **Rationale**: Neither requirements.md nor the constitution states a minimum iOS version — only
  "iOS, portrait only." Inventing a specific floor (e.g., "iOS 15+") would be an unrequested,
  unverifiable constraint. The SDK's own default is the reasonable technical decision here per
  Constitution Principle I.
- **Alternatives considered**: None — there is no documented requirement to weigh against.

## R9 — `design_tokens.dart` shape and font delivery

- **Decision**: A plain Dart class of `static const` values (colors as `Color`, type scale as
  `TextStyle`, spacing/radii as `double`) feeding a single `ThemeData` built from those constants;
  fonts (`Fraunces`, `Karla`, `IBM Plex Mono`) are bundled as local assets declared in
  `pubspec.yaml`, not fetched at runtime.
- **Rationale**: RNF08 requires zero hardcoded visual values outside this one file — a `static
  const` class makes any other hardcoded value a compile-time-visible outlier (not referencing the
  token file) rather than something only caught by review. Bundling fonts as assets (vs.
  `google_fonts`, which fetches over the network on first use) avoids adding a second runtime
  network dependency beyond the backend itself and keeps text rendering deterministic offline,
  consistent with RNF01's latency intent.
- **Alternatives considered**: `google_fonts` package — rejected: introduces a non-backend network
  fetch and a cache-miss failure mode (slow/no connection on first launch) that bundled assets don't
  have. Obtaining and vendoring the three actual font files is left as an implementation task
  (tasks.md), since this plan does not fetch external binary assets.

## R10 — Home/Chat shell scope under FR-016

- **Decision**: The Home/Chat screen F000 ships shows the fixed header (☰ + "Cerne" wordmark per
  the prototype) and an empty conversation area, plus a composer bar that is rendered but fully
  **disabled** (text field non-editable, send button non-interactive) — no fake messages, no RF04
  wiring.
- **Rationale**: FR-016 allows RF01–RF10 controls to "exist only as an inert placeholder, if at
  all." Showing the chrome disabled (rather than omitting it) keeps the screen visually faithful to
  the prototype's Tela 1 for navigation/overlay testing (User Stories 4 and 5 both exercise
  Home/Chat) without implementing any chat behavior; disabling it (rather than wiring a no-op
  handler) makes the "inert" property visible to a reviewer and to a user, not just true in code.
- **Alternatives considered**: Omitting the composer entirely and showing only an empty state —
  rejected: the chat's own BLoC/scroll-state is what User Story 5's expired-session test needs to
  observe being preserved; a composer absent today would have to be added back by the RF04 unit in
  a way that reshapes this same screen, whereas a disabled composer is forward-compatible (RF04
  only needs to enable it).
