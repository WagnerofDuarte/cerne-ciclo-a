# Quickstart: P-RF10 — Save a chat message as an entry

How to validate this unit end-to-end once implemented, mapped to spec.md's four user stories. A run guide —
interfaces are in `contracts/`, state/entities in `data-model.md`.

## Prerequisites

- RF01 and RF04 already implemented and passing — a signed-in test account can reach `/home`, send chat
  messages, and (separately) create entries via the Insertion Modal.
- At least one existing conversation with 2+ user messages, for Story 2's "save twice" and Story 4's
  "assistant has no bookmark" checks.
- A way to force a write failure for Story 3 (airplane mode toggled right before a tap, or a test double at
  the repository layer for automated tests) and, separately, a way to force an `AUTH_EXPIRED` response for the
  reauth-overlay Edge Case.
- A way to clear/forget this device's local chat cache (reinstall, or a debug-only cache-clear action) to
  exercise FR-004's "no local record of a prior success" path without needing a second physical device.

## Automated checks

```bash
fvm flutter analyze                                    # RNF06 import-shape lint
fvm flutter test --coverage
lcov --extract coverage/lcov.info 'lib/**/domain/**' -o coverage/domain.info
genhtml coverage/domain.info -o coverage/domain-html    # RNF07 gate — bookmark_status.dart, _seedBookmarks, etc.
dart test/architecture/no_bloc_imports_bloc_test.dart   # ChatBloc stays within lib/features/chat/
dart test/architecture/domain_purity_test.dart          # chat/domain/ imports neither Flutter nor chat/data/
```

`contracts/create-entry-usecase-chat-extension.md`, `contracts/chat-repository-bookmark-extension.md`, and
`contracts/chat-bloc-bookmark-extension.md` each carry the full scenario table this unit's coverage depends
on.

## Manual verification (device/Simulator)

### Story 1 — Turning a message you just wrote into a journal entry (P1)

1. Send a message in an active conversation. **Expect**: a bookmark control (outline icon) appears next to
   that message only, in its `idle` state.
2. Tap it. **Expect**: it shows a spinner (`saving`), then settles into an ochre check (`saved`), with no
   visible delay beyond the network round-trip.
3. Open "Meus Registros" (or wherever entries are listed). **Expect**: a new entry exists with that message's
   exact text as content, `source` = `chat`, and `chatMessageId` matching the message — structurally
   indistinguishable from any RF01-captured entry otherwise.
4. Leave the conversation (side menu → another screen) and come back, then fully restart the app and reopen
   it. **Expect**: the same message's bookmark still shows the ochre check, not reset to `idle` (FR-008).

### Story 2 — Saving the same message twice never creates a duplicate (P1)

1. On an already-`saved` bookmark, confirm it has no tap affordance at all (no visual "pressed" feedback, no
   network call fires even if tapped where the icon renders). **Expect**: exactly one entry still exists for
   that message afterward.
2. Clear/forget the device's local chat cache (or reinstall), then reopen the same conversation. **Expect**:
   the previously-saved message's bookmark renders `idle` again (the local record is gone) — tap it.
   **Expect**: it goes `saving` → `saved` again, and "Meus Registros" still shows exactly one entry for that
   message, never two (the backend's own idempotency, confirmed via `error-taxonomy.md`'s "never `409`, always
   `200`").

### Story 3 — A failed save never disrupts the conversation (P2)

1. Enable airplane mode, then tap an `idle` bookmark. **Expect**: `saving` briefly, then a red warning icon
   (`error`) — never stuck in `saving`.
2. While that bookmark is still `error`, send a new message, scroll the conversation, and tap a *different*
   message's bookmark (also while still offline, to confirm it independently reaches `error` too).
   **Expect**: every one of those actions works normally — sending still optimistically appends (and then
   itself fails/blocks per RF04's own offline behavior, unrelated to the bookmark), scrolling is unaffected,
   the second bookmark reaches its own `error` independently.
3. Disable airplane mode, then tap the first failed bookmark again. **Expect**: it re-attempts (`saving`) and
   reaches `saved`.
4. Force a session expiration (`AUTH_EXPIRED`) while a bookmark save is in flight. **Expect**: the existing
   "Sessão expirada" overlay appears over the chat (Edge Cases); the bookmark itself ends in `error`
   (retryable) rather than stuck in `saving`; after re-authenticating, tapping it again succeeds normally.

### Story 4 — Only your own messages can become entries (P2)

1. In a conversation with both user and assistant messages (including at least one streaming/in-progress and
   one failed assistant response, if reachable), inspect every message. **Expect**: a bookmark control is
   present on every user message and absent from every single assistant one, with no exceptions.

### Edge cases worth exercising manually at least once

- Tap a bookmark twice in rapid succession before the first tap's request resolves. **Expect**: only one
  network call fires (observable via a debug network log or a single spinner-to-settled transition, not a
  flicker of two).
- Tap the bookmark on a message the instant after sending it (before the composer's optimistic placeholder has
  been reconciled with the backend's real message id — a very narrow window, may require a slow/throttled
  connection to reliably hit). **Expect**: the tap is silently ignored; tapping again a moment later (once the
  message has a real id) works normally (research.md R6).
- A message's content at or near the entry content-length limit. **Expect**: the save either succeeds
  normally, or — if the backend's own validation rejects it — the bookmark shows `error` without crashing or
  silently dropping the attempt.
- Navigate away from a conversation while a bookmark save is in flight, then return to it. **Expect**: the
  bookmark reflects the save's actual outcome (`saved` or `error`), never a stale `saving` indicator tied to a
  request that already finished.
