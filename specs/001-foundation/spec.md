# Feature Specification: P-F000 — Foundation

**Feature Branch**: `001-foundation` (spec directory only — no git branch was created automatically; none of this repo's extension hooks are configured)

**Created**: 2026-10-11

**Status**: Draft

**Input**: User description: "P-F000 — Foundation: Build the foundation that every later unit uses (project scaffold, design tokens, HTTP client with Either/Failure error mapping, login/sign-up, splash, base navigation, expired-session overlay), as described in docs/input/requirements.md section 12, without implementing RF01–RF10, hardcoding visual values outside design_tokens.dart, or changing the backend."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Returning user logs in (Priority: P1)

A person who already has a Cerne account opens the app, enters their email and password on the login screen, and reaches the main conversation screen (Home/Chat).

**Why this priority**: Nothing else in the product — capture, chat, records, settings — is reachable without this. It is the single gate every other unit depends on.

**Independent Test**: Can be fully tested by submitting valid credentials on the login screen and confirming the app lands on Home/Chat; delivers a working, demonstrable access path on its own.

**Acceptance Scenarios**:

1. **Given** a user with a valid existing account and no active session, **When** they enter the correct email and password on the login screen and submit, **Then** they are authenticated and taken to the Home/Chat screen.
2. **Given** a user on the login screen, **When** they submit incorrect credentials, **Then** they see a clear, non-crashing error message and remain on the login screen able to retry.
3. **Given** a user with no network connection, **When** they submit the login form, **Then** they see a retryable connection-error message rather than the app hanging or crashing.

---

### User Story 2 - New user creates an account (Priority: P2)

A person without a Cerne account switches the same screen to sign-up mode, enters an email and password, and reaches Home/Chat as a newly created user.

**Why this priority**: Required for anyone without an account to enter the product at all, but it depends on the same screen and session machinery as login, so it is one step below it.

**Independent Test**: Can be fully tested by toggling to "Criar conta", submitting a new email/password pair, and confirming an account is created and the app lands on Home/Chat.

**Acceptance Scenarios**:

1. **Given** a person without an account, **When** they switch to "Criar conta" mode, enter a new email and password, and submit, **Then** an account is created and they are taken directly to Home/Chat.
2. **Given** a person entering an email that is already registered, **When** they submit the sign-up form, **Then** they see a clear error message and can correct and retry without the app crashing.

---

### User Story 3 - App launches and routes by session state (Priority: P3)

Whenever the app is opened, it shows a brief splash state, checks whether a usable session already exists, and sends the user straight to Home/Chat or to the login/sign-up screen accordingly — without ever leaving them stuck on the splash screen.

**Why this priority**: Determines where every single app session begins; it depends on User Story 1 existing but is a thin routing layer on top of it rather than new user-facing capability.

**Independent Test**: Can be fully tested by launching the app under three stored-session conditions (valid, expired-but-refreshable, none) and confirming the correct landing screen each time.

**Acceptance Scenarios**:

1. **Given** a device with a previously stored, still-valid session, **When** the app is launched, **Then** after the splash state the user lands directly on Home/Chat without re-entering credentials.
2. **Given** a device with no stored session (first launch, or after logout), **When** the app is launched, **Then** after the splash state the user lands on the login/sign-up screen.
3. **Given** a device with an expired-but-refreshable session, **When** the app is launched, **Then** the app renews the session in the background and lands on Home/Chat without prompting the user.

---

### User Story 4 - Navigating between the main screens (Priority: P4)

From Home/Chat, the user opens the side menu and moves to Meus Registros or Configurações (today, placeholders), and back, without losing their place.

**Why this priority**: Establishes the skeleton every later unit (RF06/RF07/RF05, RF09, etc.) will fill in; it has no functional payload yet, so it ranks below the screens that actually unlock product value.

**Independent Test**: Can be fully tested by opening the side menu from Home/Chat, visiting each destination, and returning, confirming Home/Chat's state is unchanged.

**Acceptance Scenarios**:

1. **Given** the user is on Home/Chat, **When** they open the side menu and select "Meus Registros", **Then** they see the Meus Registros placeholder screen and can return to Home/Chat.
2. **Given** the user is on Home/Chat, **When** they open the side menu and select "Configurações", **Then** they see the Configurações placeholder screen and can return to Home/Chat.
3. **Given** the user is on any main screen, **When** they open the side menu, **Then** the menu overlays the current screen without discarding the state underneath it.

---

### User Story 5 - Session expires during active use (Priority: P5)

While the user is actively on a screen (e.g., scrolled partway through Home/Chat), the backend session expires; an overlay appears explaining this and offering to log in again, and once they do, they return to exactly where they were.

**Why this priority**: An edge condition of an already-working session (Story 1); important for trust and data safety, but it cannot be exercised until login and at least one screen exist.

**Independent Test**: Can be fully tested by forcing a session-expired response while a screen is in a known state, confirming the overlay appears over it unchanged, and confirming re-authentication restores that exact state.

**Acceptance Scenarios**:

1. **Given** the user is actively viewing a screen in a particular state (e.g., a given scroll position), **When** the backend reports the session has expired, **Then** a "Sessão expirada" overlay appears on top of the current screen without resetting its state.
2. **Given** the "Sessão expirada" overlay is visible, **When** the user taps "Entrar novamente" and re-authenticates successfully, **Then** the overlay is dismissed and the underlying screen is restored exactly as it was.

---

### Edge Cases

- Submitting the login or sign-up form with an empty field shows an inline validation message immediately, with no network call made.
- The backend rejects a login or sign-up submission as malformed (non-retryable) — this is shown and handled distinctly from a timeout or offline condition (retryable).
- The stored access token is present but its refresh token is itself invalid or expired at launch — the user is routed to the login screen, never left stuck on the splash state.
- The session expires a second time while the user is still dismissing a "Sessão expirada" overlay from the first expiration — the overlay persists/reappears rather than letting the user proceed with a stale session.
- A user opens a placeholder screen (Meus Registros, Configurações) before its owning unit is built — it renders cleanly as "not yet available" rather than a blank or broken screen.
- The app is backgrounded mid-submission of login or sign-up — on resume, the request either completes normally or fails cleanly, and never results in a duplicate account or a duplicate session.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST be organized so that every feature added from this unit onward follows one fixed folder convention, so later units have a single place to add their own code without restructuring the foundation.
- **FR-002**: The system MUST define every visual value (color, typography, spacing, corner radius) used anywhere in the app in exactly one central place; no screen delivered by this unit may define a visual value anywhere else.
- **FR-003**: The system MUST provide a single way for any feature to call the backend that always yields either a success result or a typed failure — never an unhandled crash.
- **FR-004**: The system MUST translate every backend error response's error code, message, and retryable flag into a failure the UI can act on, so screens can tell a retryable problem (e.g., timeout) from one that is not (e.g., invalid credentials).
- **FR-005**: The system MUST address the backend using the documented real request path for each operation, not the contract's documentation-only path.
- **FR-006**: Users MUST be able to create a new account by submitting an email and password from the sign-up mode of the login screen.
- **FR-007**: Users MUST be able to authenticate with an existing email and password from the login mode of the same screen.
- **FR-008**: Users MUST be able to toggle between login and sign-up mode on the same screen without being sent to a different screen.
- **FR-009**: The system MUST check, on every app launch, whether a usable session already exists — renewing it first if it is merely expired-but-renewable — and route the user to Home/Chat when one exists or to the login screen otherwise.
- **FR-010**: The system MUST show a splash state while this session check (and any related background preparation) is in progress, before routing the user anywhere.
- **FR-011**: Users MUST be able to reach Home/Chat, Meus Registros, and Configurações from a side menu, and return to Home/Chat from either of them.
- **FR-012**: Meus Registros and Configurações MUST appear as clearly-labeled placeholder screens with no functional behavior from later requirements (RF01–RF10), reserving space for the units that will fill them in.
- **FR-013**: The system MUST show a "Sessão expirada" overlay on top of whatever screen the user is on when the backend reports the session has expired, without discarding that screen's state underneath.
- **FR-014**: Users MUST be able to dismiss the "Sessão expirada" overlay by re-authenticating, after which the screen underneath MUST be restored to its prior state.
- **FR-015**: The system MUST present a clear, non-crashing message for every error condition that sign-up, login, session-renewal, or session-check can return.
- **FR-016**: This unit MUST NOT implement the functional behavior of any RF01–RF10 requirement; any screen or control belonging to one of them MUST exist only as an inert placeholder, if at all.
- **FR-017**: This unit MUST NOT modify the backend, its contract, or its configuration in any way.

### Key Entities

- **Session**: Represents whether the user is currently authenticated — holds the information needed to stay logged in and to know when it has expired or can be silently renewed. Determines whether a launch routes to Home/Chat or to the login screen, and whether an active screen receives the "Sessão expirada" overlay.
- **Account**: The identity a person signs up with or logs into — an email address and the credential tied to it.
- **Backend Failure**: The error outcome every call introduced by this unit (sign-up, login, refresh, session check) can produce — carries enough information to distinguish a retryable problem from a non-retryable one, and to choose the message shown to the user.
- **Placeholder Destination**: A navigable screen (Meus Registros, Configurações) that exists so later units have somewhere to add their functionality, but carries no behavior of its own in this unit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of returning users with a valid stored session reach Home/Chat automatically after the splash state, with no login step required.
- **SC-002**: A new user can go from the sign-up form to a usable Home/Chat screen in a single successful attempt, with no intermediate screen other than the brief splash state.
- **SC-003**: Every error condition that sign-up, login, session-renewal, and session-check can return produces a readable on-screen message rather than a blank screen, a crash, or an indefinite loading state.
- **SC-004**: A user can reach each of the main screens (Home/Chat, Meus Registros, Configurações) from the side menu, and return to Home/Chat, in 2 taps or fewer, every time.
- **SC-005**: When a session expires while a screen is in a particular state, that same state (e.g., scroll position, visible content) is unchanged after the user re-authenticates, in every observed case.
- **SC-006**: Every screen delivered by this unit visually matches the prototype's documented colors, typography, and spacing, with zero visual values defined outside the single central source.

## Assumptions

- Biometric/PIN authentication (RF03) is its own delivery unit, built immediately after this one. Until it exists, the splash state routes directly between itself and the login/sign-up screen — the biometric step shown in the prototype's navigation map is intentionally skipped for this unit and will be inserted by the RF03 unit.
- Re-authenticating from the "Sessão expirada" overlay goes to the login screen (not to a biometric step), for the same reason — RF03 is not yet part of the app.
- Sign-up collects only an email and a password, matching both the prototype (which shows no additional fields) and the backend's sign-up contract.
- Session renewal is attempted silently in the background whenever a request fails because the session has merely expired; the "Sessão expirada" overlay is shown only once silent renewal itself is not possible.
- Where this unit's side menu is shown, "Planos de Ação" may exist as an inert placeholder entry per the product's extension-feature policy, but is not required navigation for this unit — only Home/Chat, Meus Registros, and Configurações are.
- Access and refresh tokens are kept on the device between app launches so a returning user is not asked to log in every time; the specific on-device storage mechanism is an implementation choice, not fixed by this specification.
- Every error this unit's calls (sign-up, login, refresh, session check) can return is one of the backend's fixed, documented error codes; no other error shape is expected from these calls.
