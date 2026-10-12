# Data Model: P-F000 — Foundation

Source: spec.md §Key Entities, requirements.md §§8, 11, 13, prototype-extract.md §3. Entities here
are either in-memory domain objects (Session, Account, Failure) or presentation-only state
(AuthFormMode) — F000 introduces no local database.

## Session

Represents whether the user is currently authenticated; drives splash routing (FR-009) and the
"Sessão expirada" overlay (FR-013).

| Field | Type | Notes |
|---|---|---|
| `accessToken` | `String` | From `auth-login`/`auth-signup`/`auth-refresh`'s `session.accessToken`. Stored, never logged. |
| `refreshToken` | `String` | From the same responses' `session.refreshToken`. Stored, never logged. |
| `expiresAt` | `int` (unix seconds) | From `session.expiresAt` (signup/login) or `auth-session`'s `data.expiresAt`. |
| `tokenType` | `String` | From `session.tokenType` (expected `"bearer"`); carried through unchanged. |
| `account` | `Account` | Denormalized from the same response's `user` object. |

**Derived state — `SessionStatus`** (domain enum/sealed type consumed by `SessionBloc`):

```
checking            # splash in progress — auth-session call (or no stored tokens yet checked)
authenticated(Session)
expiredRenewable    # auth-session returned AUTH_EXPIRED; auth-refresh not yet attempted/resolved
unauthenticated     # no stored tokens, or refresh itself failed (AUTH_INVALID/AUTH_EXPIRED on the refresh token)
```

**State transitions** (FR-009, FR-010, User Story 3, Edge Cases):

```
[app launch]
  no stored tokens            -> unauthenticated -> route: Login/SignUp
  stored tokens present       -> checking (GET auth-session, Bearer = stored accessToken)
      200                     -> authenticated -> route: Home/Chat
      401 AUTH_EXPIRED         -> expiredRenewable -> POST auth-refresh (Bearer = anon key, body.refreshToken)
            200                -> authenticated (new Session stored) -> route: Home/Chat
            401 (AUTH_INVALID | AUTH_EXPIRED) -> clear() -> unauthenticated -> route: Login/SignUp   (never left on splash — see R7)
      401 AUTH_INVALID         -> clear() -> unauthenticated -> route: Login/SignUp   (token itself rejected —
                                   e.g. the account was deleted on the backend; refreshing cannot help, so this
                                   is NOT treated as a networkError/retry case — never left on splash)
      NETWORK_TIMEOUT | NETWORK_OFFLINE -> splash shows retry affordance, no route change yet (R7)

[active screen, any later authenticated call returns AUTH_EXPIRED]
  authenticated -> attempt silent auth-refresh in background
      success -> authenticated, screen state untouched, no overlay shown
      failure -> expiredRenewable -> show "Sessão expirada" overlay over the current screen (state preserved underneath)

["Sessão expirada" overlay visible]
  user taps "Entrar novamente", re-authenticates (auth-login) -> authenticated, overlay dismissed, underlying screen state restored
  a second AUTH_EXPIRED arrives while the overlay is still up -> overlay persists/reappears (Edge Cases) — never silently proceeds with the stale session
```

## Account

The identity a person signs up with or logs into (spec.md Key Entities; requirements.md §8 `users`
table, scoped to what the auth endpoints return).

| Field | Type | Notes |
|---|---|---|
| `id` | `String` (uuid) | From `user.id` in signup/login responses, or `auth-session`'s `data.user.id`. |
| `email` | `String` | From `user.email`. Also the sign-up/login form input (FR-006, FR-007). |

Password is never modeled as a field on `Account` — it exists only transiently as sign-up/login
form input and an outbound request-body value; it is never stored or logged.

## Backend Failure

The error outcome every call this unit introduces (`auth-signup`, `auth-login`, `auth-refresh`,
`auth-session`) can produce, carrying enough information to pick a message and a retry affordance
(FR-004, FR-015). Modeled as a sealed `Failure` hierarchy in `core/network/failure.dart`, covering
**all 13** backend codes per research.md R6 (not just the ones reachable from F000's own calls):

| `Failure` subtype | Source `code` | HTTP | `retryable` |
|---|---|---|---|
| `AuthExpiredFailure` | `AUTH_EXPIRED` | 401 | no |
| `AuthInvalidFailure` | `AUTH_INVALID` | 401 | no |
| `NetworkTimeoutFailure` | `NETWORK_TIMEOUT` | 504 | yes |
| `NetworkOfflineFailure` | `NETWORK_OFFLINE` | *(no response)* | yes |
| `ValidationFailure` | `VALIDATION_ERROR` | 400 | no |
| `PiiCheckFailedFailure` | `PII_CHECK_FAILED` | 502 | yes |
| `EmbeddingFailedFailure` | `EMBEDDING_FAILED` | 502 | yes |
| `AiGenerationTimeoutFailure` | `AI_GENERATION_TIMEOUT` | 504 | yes |
| `NotFoundFailure` | `NOT_FOUND` | 404 | no |
| `RateLimitedFailure` | `RATE_LIMITED` | 429 | yes |
| `ExportEmptyPeriodFailure` | `EXPORT_EMPTY_PERIOD` | 400 | no |
| `PayloadTooLargeFailure` | `PAYLOAD_TOO_LARGE` | 413 | no |
| `OcrNoTextFailure` | `OCR_NO_TEXT` | 400 | no |

Every subtype carries the raw `message` (String) and `requestId` (String) through unchanged; `code`
and `retryable` are implied by the subtype itself (each is a fixed pair per the closed taxonomy).
F000's own screens only ever construct/handle `AuthExpiredFailure`, `AuthInvalidFailure`,
`NetworkTimeoutFailure`, `NetworkOfflineFailure`, `ValidationFailure`, and `RateLimitedFailure`; the
remaining seven exist so later units never redefine this file.

**Validation rule**: a `NETWORK_OFFLINE` failure is synthesized client-side by `ApiClient` (dio)
when a request ends with no response at all (connection error) — it is the one code the backend
itself never emits as an HTTP response (error-taxonomy.md).

## Placeholder Destination

A navigable screen that exists so a later unit has somewhere to add functionality, with no
behavior of its own in F000 (FR-012).

| Field | Type | Notes |
|---|---|---|
| `route` | `String` | `/records` or `/settings`. |
| `label` | `String` | "Meus Registros" / "Configurações" — exact prototype strings. |

No other state. Rendered as a static "ainda não disponível"-style message per the prototype's
general empty-state pattern; no entity/list data is fetched.

## Presentation-only state (not persisted, not a domain entity)

- **`AuthFormMode`** (`login | signUp`) — which mode the single login/sign-up screen is toggled to
  (FR-008). Lives in `AuthBloc`'s state, reset to `login` each time the screen is (re-)entered.
- **Form field errors** (empty-field validation, Edge Cases) — transient widget/bloc state, shown
  inline, never reaches the network layer (no call is made for an empty field).

## Design Tokens (`lib/core/design_tokens.dart`)

Transcribed verbatim from prototype-extract.md §3 — this file does not interpret or round any
value, it copies the panel.

**Colors** (14 named constants): `colorPrimary #1F3D34`, `colorPrimaryPressed #16281F`,
`colorOnPrimary #F5F1E8`, `colorAccent #C98A3E`, `colorOnAccent #241C0D`, `colorSecondary #7C8B6F`,
`colorSurfaceBg #F2EFE7`, `colorSurfaceElevated #FBF9F4`, `colorBorder #E1DACB`,
`colorTextPrimary #241F19`, `colorTextSecondary #6B6255`, `colorError #B3402A`,
`colorSuccess #4C6B4F`, `colorWarningSync #C98A3E`, `colorInfoOffline #5C7A93`. F000 additionally
needs the two screen-specific colors called out as not in the panel but required for faithful
rendering of elements it ships: user chat bubble `#D9DFD3` (`colorChatBubbleUser`) — used by the
Home/Chat shell's composer preview area — and category-chip text `#3F4A38` is **not** needed by
F000 (no chips exist before RF06/RF07) and is therefore left for the unit that introduces chips.

**Typography** (8 named `TextStyle` constants, per the table in prototype-extract.md §3):
`textDisplayLg`, `textHeadlineMd`, `textTitleLg`, `textTitleSm`, `textBodyLg`, `textBodyMd`,
`textLabelMd`, `textMonoCaption` — font family/weight/size/line-height exactly as specified
(Fraunces, Karla, IBM Plex Mono; see research.md R9 for asset delivery).

**Spacing**: `spacingXs 4`, `spacingSm 8`, `spacingMd 16`, `spacingLg 24`, `spacingXl 32`,
`spacing2xl 48` (all `double`, dp).

**Radii**: `radiusSm 8`, `radiusMd 16`, `radiusLg 24`, `radiusFull 999` (all `double`, dp).

**Elevation**: `elevation1` and `elevation2` as `BoxShadow`/`List<BoxShadow>` constants matching
the two shadow specs in prototype-extract.md §3.

F000 does not need the `Spine`, `Icons` (beyond `list`/`plus`/`gear`/`notebook`/`chat-circle-text`
for its own 5 screens), or component-level tokens (bookmark, sync badge, export card, etc.) that
belong to later units' screens — those are added to this same file when those units need them,
never duplicated elsewhere.
