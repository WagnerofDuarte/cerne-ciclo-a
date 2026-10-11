<!--
Sync Impact Report
Version change: (unratified template) → 1.0.0
Rationale: Initial ratification. The prior file on disk still contained only
unfilled template placeholders ([PROJECT_NAME], [PRINCIPLE_1_NAME], ...) and
never expressed concrete governance, so this is treated as the first adopted
version rather than an amendment.
Modified principles: n/a (no prior concrete principles existed)
Added sections:
  - Core Principles I–V (Product Source of Truth; Fixed Technology Stack;
    Backend Boundary — Frozen Backend, No Direct AI Calls; Design Token
    Discipline & Visual Fidelity; Clean Architecture Folder Convention)
  - Quality Standards (RNF01–RNF09)
  - Scope & Delivery Boundaries
  - Governance
Removed sections: none
Deferred placeholders / TODOs: none — all fields resolved from user-supplied
principles and docs/input/requirements.md.
Templates reviewed for alignment: not modified by this command (out of scope
per the constitution command's scope guard); plan/spec/tasks templates should
be checked against Principles II, III and V on their next edit.
-->

# Cerne Constitution

## Core Principles

### I. Product Source of Truth
`docs/input/` — `requirements.md`, `prototype/`, and `backend/` — is the
authoritative source for product behavior. `requirements.md` defines
functional and quality requirements, screens, the API surface, delivery
order, and technical constraints; `prototype/` is the frozen visual
reference and its token/state extract; `backend/` documents the existing
API, error taxonomy, screen-state map, sync-badge semantics, and fixtures.
Where these documents are silent, implementers MUST make a reasonable
technical decision rather than block on clarification. Files under
`docs/input/` are frozen inputs and MUST NOT be edited by anyone working in
this repository.

Rationale: a reflective-journaling app with a frozen, already-documented
backend has exactly one place where ambiguity should be resolved — the
product input — so decisions stay traceable and the backend contract stays
stable.

### II. Fixed Technology Stack
The app is built with Flutter and Dart at the version pinned via `fvm`,
using `flutter_bloc` for state management and Clean Architecture with three
layers per feature. Error handling MUST use `fpdart`, with every repository
returning `Either<Failure, T>`. Test doubles MUST use `mocktail`. Speech-to-
text runs on-device via `whisper_ggml`; audio content MUST NEVER be sent to
the backend. The shipping platform is iOS. Choices not fixed here — routing,
HTTP client, local cache, dependency injection, secure storage, biometrics,
and charting — are open implementation decisions.

Rationale: a single, non-negotiable stack removes a whole category of
architectural debate and keeps the codebase consistent across features
built by different contributors or at different times.

### III. Backend Boundary — Frozen Backend, No Direct AI Calls
The backend is already built and frozen. The app consumes it strictly as
documented in `docs/input/backend/`, including its API contract
(`docs/input/backend/api/openapi.yaml`); the app MUST NOT change the
backend, its API contract, or its configuration. All AI features, including
semantic search, are provided exclusively by the backend — the app MUST
NEVER call an AI provider directly. Configuration and credentials come from
a project-root `.env` with exactly two variables: `FUNCTIONS_BASE_URL` and
`SUPABASE_ANON_KEY`. Every call to `{FUNCTIONS_BASE_URL}/<function>` MUST
carry the header `apikey: <SUPABASE_ANON_KEY>`. The `Authorization: Bearer`
header carries `SUPABASE_ANON_KEY` for operations that need no user session
(sign-up, login, refresh) and the user's access token for every operation
marked `bearerAuth` in the OpenAPI contract. `.env` and any credential MUST
NEVER be committed.

Rationale: the backend and its AI integrations are out of this project's
scope and already relied upon elsewhere; treating them as an immutable,
narrowly-accessed contract prevents scope creep and accidental coupling or
credential leakage.

### IV. Design Token Discipline & Visual Fidelity
`lib/core/design_tokens.dart` is the single source of colors, typography,
spacing, and radii. No visual value MAY be hardcoded anywhere else. The UI
MUST be faithful to `docs/input/prototype/`. UI text MUST be in Portuguese,
exactly as written in the prototype; code identifiers, comments, and project
documentation MUST be in English.

Rationale: a single token source makes visual fidelity (RNF08) mechanically
checkable, and separating UI language (Portuguese, matching the frozen
prototype) from code language (English) keeps the codebase reviewable while
preserving the product's voice.

### V. Clean Architecture Folder Convention
Code MUST follow the folder convention:
```
lib/
  core/
  features/
    <feature>/
      data/
      domain/
      presentation/
```
The domain layer MUST comply with RNF06: zero layer violations — it MUST
NOT import `package:flutter` nor any class from a feature's `data/` layer.

Rationale: a fixed, enforced folder shape and a flutter/data-free domain
layer make the domain independently testable and keep business rules
portable regardless of UI or persistence choices.

## Quality Standards (RNF01–RNF09)

These targets from `docs/input/requirements.md` are binding quality gates:

- **RNF01 — Interaction latency**: a local action MUST be reflected in the
  UI in under 100 ms; any network call taking longer than 300 ms MUST show a
  loading indicator.
- **RNF02 — PII stripping**: performed backend-side via Claude Haiku 4.5
  with a structured prompt / tool use, not a dedicated NER model; the app
  implements no PII-detection logic of its own.
- **RNF03 — Zero data retention**: a backend-side policy; the app MUST NOT
  introduce its own retention beyond what the backend requires.
- **RNF04 — Row Level Security (RLS)**: enforced backend-side; the app MUST
  assume RLS is authoritative and MUST NEVER attempt to bypass it.
- **RNF05 — Hard delete of account and data (LGPD)**: the app MUST expose
  the account-deletion flow (`DELETE /account`) from Settings.
- **RNF06 — Zero layer violations**: see Principle V; 0 violations is the
  target.
- **RNF07 — Domain test coverage**: `lib/**/domain/**` MUST reach at least
  80% test coverage.
- **RNF08 — Visual fidelity**: every screen MUST match the prototype's
  color, typography, and spacing, with 0 hardcoded visual values outside
  `design_tokens.dart`.
- **RNF09 — Consistent network-error handling**: every repository MUST use
  the `Either<Failure, T>` pattern via `fpdart`; every write endpoint (5
  endpoints) MUST handle timeout, malformed response, and no-connection
  failures, each covered by `mocktail` tests (15 of 15 scenarios).

## Scope & Delivery Boundaries

- Functional requirements MUST be implemented in the delivery order given in
  `docs/input/requirements.md`.
- Extension features (section 2 of `requirements.md`) are explicitly out of
  scope and MUST NOT be implemented beyond an optional placeholder menu
  entry.
- The following actions are prohibited in this repository:
  - Changing the backend, its API contract, or its configuration.
  - Calling AI providers directly from the app.
  - Writing visual values (colors, font sizes, spacing, radii) outside
    `design_tokens.dart`.
  - Implementing extension features.
  - Committing `.env` or any credential.
  - Editing files under `docs/input/`.

## Governance

This constitution supersedes any conflicting practice, template, or
instruction used in this repository. Every plan, spec, task list, and
review MUST verify compliance with these principles before work is
considered done; any deviation MUST be justified in writing in the relevant
artifact (plan or PR description) or the work MUST be rejected.

**Amendment procedure**: amendments are proposed by editing this file,
describing the change and rationale, and are adopted once the project owner
accepts the change (commit to this file constitutes adoption in this
single-maintainer project). Each amendment MUST update the Sync Impact
Report at the top of this file and the version/date line below.

**Versioning policy** (semantic versioning for this document):
- **MAJOR** — backward-incompatible governance or principle removal/
  redefinition.
- **MINOR** — a new principle or section added, or materially expanded
  guidance.
- **PATCH** — wording clarifications, typo fixes, non-semantic refinements.

**Compliance review**: any change to `lib/` MUST be checked against the
Core Principles and Quality Standards above before merge; violations of
RNF06–RNF09 in particular are release blockers.

**Version**: 1.0.0 | **Ratified**: 2026-10-11 | **Last Amended**: 2026-10-11
