import 'package:cerne/core/network/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:equatable/equatable.dart';

sealed class RecordsState extends Equatable {
  const RecordsState();

  @override
  List<Object?> get props => [];
}

class RecordsLoading extends RecordsState {
  const RecordsLoading();
}

class RecordsLoadFailure extends RecordsState {
  const RecordsLoadFailure(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

class RecordsLoaded extends RecordsState {
  const RecordsLoaded({
    required this.entries,
    required this.nextCursor,
    required this.isLoadingMore,
    this.pageLoadFailure,
  });

  /// Merged + deduped, newest-to-oldest.
  final List<Entry> entries;
  final String? nextCursor;
  final bool isLoadingMore;

  /// A further-page fetch failed; `entries` above stay intact, retryable.
  final Failure? pageLoadFailure;

  bool get hasReachedEnd => nextCursor == null;
  bool get isEmpty => entries.isEmpty;

  @override
  List<Object?> get props => [entries, nextCursor, isLoadingMore, pageLoadFailure];
}
