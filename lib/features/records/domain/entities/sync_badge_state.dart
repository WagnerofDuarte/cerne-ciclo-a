/// The three states a record card's synchronization badge can show
/// (`docs/input/backend/sync-badge.md`).
enum SyncBadgeState { synchronized, synchronizing, error }

/// The outcome of a locally-initiated write that hasn't yet been reconciled
/// against the server. `null` means no local write is in flight for this
/// entry at all.
enum LocalWriteOutcome { pending, failed }

/// A pure, total function over `sync-badge.md`'s model — takes no
/// session/auth-related input at all, trivially satisfying FR-005's
/// independence requirement (research.md R6).
class SyncBadge {
  const SyncBadge._();

  static SyncBadgeState derive(LocalWriteOutcome? localWrite) =>
      switch (localWrite) {
        null => SyncBadgeState.synchronized,
        LocalWriteOutcome.pending => SyncBadgeState.synchronizing,
        LocalWriteOutcome.failed => SyncBadgeState.error,
      };
}
