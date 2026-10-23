# Bookmark Feature Requirements Checklist: P-RF10 — Save a chat message as an entry

**Purpose**: Validate the quality (completeness, clarity, consistency, measurability, and coverage) of
spec.md's requirements for the chat-message bookmark feature — the four-state control, its save/idempotency
behavior, its error resilience, and its scoping to user-only messages — before implementation proceeds.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md)

**Review Ownership**: This checklist is a reviewer-owned requirements-quality review artifact. Mark an item
`[x]` only when the reviewer determines the requirements-quality criterion is satisfied — not when the
underlying implementation behavior has been verified.
**Marker Semantics**: `[x]` means the criterion has been reviewed and satisfied for requirements quality. It
does not mean implementation work is complete.

## Bookmark State Machine Completeness & Clarity

- [ ] CHK001 Are all four bookmark states (`idle`, `saving`, `saved`, `error`) and every permitted transition
  between them fully enumerated, with no transition left implicit? [Completeness, Spec §FR-002/FR-003]
- [ ] CHK002 Is the claim that the `saved` state is terminal and non-interactive stated precisely enough to
  rule out an alternate reading where a visibly `saved` bookmark could still be tapped? [Clarity, Spec §FR-003]
- [ ] CHK003 Are the requirements for what happens when a bookmark is in `saving` and receives another tap
  (ignored vs. queued vs. erroring) unambiguous? [Clarity, Spec §FR-007]
- [ ] CHK004 Is the requirement for re-entering `saving` from `error` on retry distinguished clearly enough
  from the first-ever `idle → saving` transition, so a reader cannot conflate "first save" and "retry" as
  needing different backend calls? [Clarity, Spec §FR-005, US3]
- [ ] CHK005 Does the spec define what state a bookmark must render in in the window before the client has
  determined whether a given message was already saved (e.g., immediately after a conversation loads)?
  [Gap, Spec §FR-008]

## Duplicate-Prevention & Idempotency Requirement Quality

- [ ] CHK006 Is "the existing entry is reused" (rather than a new entry being created) stated as an
  observable, testable outcome rather than only as an internal implementation goal? [Measurability, Spec
  §FR-004]
- [ ] CHK007 Are the two distinct duplicate-risk scenarios — a literal re-tap on an already-`saved` control,
  and a save retried with no local record of a prior success — both covered by requirements, and is the
  boundary between them (one is a non-event because `saved` is non-interactive, the other is the real
  idempotency path) unambiguous? [Consistency, Spec §FR-004, US2]
- [ ] CHK008 Is the source of the duplicate-prevention guarantee (backend idempotency vs. a client-side
  mechanism) stated clearly enough that a reader would not design a redundant client-side dedup check against
  the requirements alone? [Clarity, Spec §Assumptions]
- [ ] CHK009 Are requirements defined for what the bookmark must display while duplicate-safety is being
  resolved (i.e., a retried save against an already-saved message), so the UI outcome during that window is
  specified and not just the end state? [Gap, Spec §FR-004]

## Error & Offline Resilience Requirement Quality

- [ ] CHK010 Are all distinct failure causes called out in the spec (no connection, timeout, other write
  failure, post-write pipeline failure) required to produce the same observable `error` state, or does the
  spec leave room for cause-specific UI that isn't otherwise defined? [Consistency, Spec §FR-005, Edge Cases]
- [ ] CHK011 Is "MUST NOT block, delay, or otherwise affect any other part of the chat screen" quantified or
  made objectively verifiable, or does it rely on a reader's subjective judgment of what counts as "affect"?
  [Measurability, Spec §FR-006]
- [ ] CHK012 Are requirements defined for the bookmark's state when a save is in flight and the user
  navigates away and back before it resolves, covering both eventual outcomes (success and failure)? [Edge
  Case, Spec §Edge Cases]
- [ ] CHK013 Does the spec define bookmark behavior requirements for the session-expiry overlay scenario in
  enough detail to be independently verifiable (e.g., what the bookmark shows immediately after
  re-authentication), or only the qualitative claim that it is "not stuck"? [Clarity, Spec §Edge Cases]
- [ ] CHK014 Are requirements for a save failing at/near the content length limit specific enough to
  distinguish "succeeds normally" from "surfaces a backend validation error as the error state," or could a
  reader implement only one of the two outcomes and still believe they satisfied the requirement? [Clarity,
  Spec §Edge Cases]

## Message-Scoping Requirement Quality

- [ ] CHK015 Is "every user message" scoped precisely enough to state whether it includes messages in every
  delivery/status condition (sending, failed-to-send, optimistic/not-yet-confirmed), or is that left to
  inference? [Completeness, Spec §FR-001]
- [ ] CHK016 Are the named exceptions ("insight cards," "partial/failed assistant responses") sufficient to
  cover every assistant-rendered UI element the chat screen can produce, or could an unlisted assistant-side
  element exist that the requirement doesn't explicitly exclude? [Coverage, Spec §FR-001]
- [ ] CHK017 Does the spec define requirements for a message whose authorship is ambiguous or system-
  generated (neither a clear user message nor a clear assistant response), or is that case assumed not to
  exist without being stated? [Gap, Assumption]

## Cross-Requirement Consistency

- [ ] CHK018 Are the `occurredAt`/timestamp requirements (entry dated to the message's own send time, not the
  tap time) consistent between the Assumptions section and every acceptance scenario that describes a saved
  entry's content? [Consistency, Spec §Assumptions, §FR-003]
- [ ] CHK019 Is the requirement that chat-sourced entries be "structurally indistinguishable" from RF01
  entries (US1, Scenario 3) consistent with FR-003's requirement that `source` and `chatMessageId` always
  differ for chat-sourced entries, without one requirement implicitly contradicting the other's intent? [Consistency, Spec §US1, §FR-003]
- [ ] CHK020 Is the shared entry-creation interface requirement (FR-009) stated with enough precision to be
  checked against the spec alone (e.g., "same use case," not "same effect"), given that the exact contract
  shape is explicitly deferred to planning? [Clarity, Spec §FR-009, §Assumptions]

## Acceptance Criteria & Success Criteria Measurability

- [ ] CHK021 Can SC-001 through SC-005 each be evaluated as pass/fail using only information available from
  the spec, without requiring an implementer's own interpretation of an undefined term? [Measurability, Spec
  §Success Criteria]
- [ ] CHK022 Does SC-005's qualifier ("where the client has a way to know the save already succeeded") risk
  making the success criterion unfalsifiable, or is the boundary of "has a way to know" defined elsewhere in
  the spec precisely enough to make the criterion testable? [Ambiguity, Spec §SC-005]

## Notes

- Mark items `[x]` only after review confirms the requirement-quality criterion is satisfied.
- Leave items unchecked when they still require clarification, correction, or reviewer evaluation.
- `/speckit-implement` reads checklist checkbox state as a gate and must not modify markers.
- `checklists/requirements.md` has a separate built-in lifecycle maintained by `/speckit-specify` and
  `/speckit-clarify` — this file is a distinct, custom checklist and does not replace it.
