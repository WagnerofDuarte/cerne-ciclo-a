import 'package:equatable/equatable.dart';

sealed class RecordsEvent extends Equatable {
  const RecordsEvent();

  @override
  List<Object?> get props => [];
}

/// `RecordsPage.initState` — triggers the first page fetch.
class RecordsStarted extends RecordsEvent {
  const RecordsStarted();
}

/// The list's `ScrollController` crosses a near-bottom threshold, and
/// `!hasReachedEnd && !isLoadingMore`.
class NextPageRequested extends RecordsEvent {
  const NextPageRequested();
}

/// The user taps "Tentar novamente" on a failed first load
/// (`RecordsLoadFailure`) or a failed further-page load
/// (`RecordsLoaded.pageLoadFailure`).
class PageLoadRetried extends RecordsEvent {
  const PageLoadRetried();
}

/// `RecordsPage`, once the insertion-modal `showModalBottomSheet` future
/// resolves (research.md R10) — re-merges `cachedEntries` into the currently
/// displayed list, no network call.
class RecordsLocalCacheRefreshed extends RecordsEvent {
  const RecordsLocalCacheRefreshed();
}
